require [
  'base/js/namespace'
  'jquery'
  'thebe/dotimeout'
  'notebook/js/notebook'
  'thebe/cookies'
  'contents'
  'services/config'
  'base/js/utils'
  'base/js/page'
  'base/js/events'
  'notebook/js/actions'
  'notebook/js/kernelselector'
  'services/kernels/kernel'
  'codemirror/lib/codemirror'
  'custom/custom'
], (IPython, $, doTimeout, notebook, cookies, contents, configmod, utils, page, events, actions, kernelselector, kernel, CodeMirror, custom) ->

  class Thebe
    default_options:
      # jquery selector for elements we want to make runnable 
      selector: 'pre[data-executable]'
      # the url of either a tmnb server or a notebook server
      # if it contains "spawn/", assume it's a tmpnb server
      # otherwise assume it's a notebook url
      url: 'http://192.168.59.103:8000/spawn/'
      # set to false to not add controls to the page
      prepend_controls_to: 'html'
      # Automatically load necessary css for codemirror and jquery ui
      load_css: true
      # Automatically load mathjax js
      load_mathjax: true
      # show messages from .log
      debug: true


    # Take our two basic configuration options
    constructor: (@options={})->
      # just for debugging
      window.thebe = this
      # important flag
      @has_kernel_connected = false

      # set options to defaults for unset keys
      # and break out some commonly used options
      {@selector, @url, @debug} = _.defaults(@options, @default_options)

      # if we've been given a non blank url, make sure it has a trailing slash
      if @url then @url = @url.replace(/\/?$/, '/')
      
      # if it contains /spawn, it's a tmpnb url, not a notebook url
      if @url.indexOf('/spawn') isnt -1
        @log 'this is a tmpnb url'
        @tmpnb_url = @url
        @url = ''

      # we break the notebook's method of tracking cells, so do it ourselves
      @cells = []
      @setup_ui()
      # the jupyter global event object
      @events = events
      # we only ever want the first call
      @spawn_handler = _.once(@spawn_handler)
      # Does the user already have a container running
      thebe_url = cookies.getItem 'thebe_url'
      # (passing a notebook url takes precedence over a cookie)
      if thebe_url and @url is ''
        @check_existing_container(thebe_url)
      else
        @start_notebook()
    
    # CORS + redirects + are crazy, lots of things didn't work for this
    # this was from an example is on MDN
    call_spawn:(cb)=>
      @log 'call spawn'
      invo = new XMLHttpRequest
      invo.open 'GET', @tmpnb_url, true
      invo.onreadystatechange = (e)=> @spawn_handler(e, cb)
      invo.onerror = => 
        @set_state('disconnected')
      invo.send()

    check_existing_container: (url, invo=new XMLHttpRequest)->
      # no trailing slash for api url
      invo.open 'GET', url+'api', true
      invo.onerror = (e)=>  @set_state('disconnected')
      invo.onload = (e)=>
        # if we can parse the response, it's the actual api
        try
          JSON.parse e.target.responseText
          @url = url
          @start_notebook()
          @log 'cookie was right, use that'
        # otherwise it's a notebook_not_found, a page that would js redirect you to /spawn
        catch
          @start_notebook()
          @log 'cookie was wrong/dated, call spawn'
      # Actually send the request
      invo.send()

    spawn_handler: (e, cb) =>
      # is the server up?
      if e.target.status is 0
        @set_state('disconnected')
      # is it full up of active containers?
      if e.target.responseURL.indexOf('/spawn') isnt -1
        @log 'server full'
        @set_state('full')
      # otherwise start the notebook, passing our user's path
      else
        @url = e.target.responseURL.replace('/tree', '/')
        @start_kernel(cb)
        # @start_notebook() # get rid of this XXX
        cookies.setItem 'thebe_url', @url

    build_notebook: =>
      # don't even try to save or autosave
      @notebook.writable = false

      @notebook._unsafe_delete_cell(0)

      $(@selector).each (i, el) =>
        cell = @notebook.insert_cell_at_bottom('code')
        cell.set_text $(el).text()
        button = $("<button class='run' data-cell-id='#{i}'>run</button>")
        $(el).replaceWith cell.element
        # cell.refresh()
        @cells.push cell
        $(cell.element).prepend button
        cell.element.removeAttr('tabindex')
        # otherwise cell.js will throw an error
        cell.element.off 'dblclick'

        # TODO, move button stuff elsewhere
        # setup run button
        button.on 'click', (e) =>
          if not @has_kernel_connected
            @before_first_run =>
              button.text('running').addClass 'running'
              cell.execute()
          else
            button.text('running').addClass 'running'
            cell.execute()
      
      @events.on 'kernel_idle.Kernel', (e, k) =>
        @set_state('idle')
        $('button.run.running').removeClass('running').text('run')#.text('ran').addClass 'ran'
      @notebook_el.hide()
      @events.on 'kernel_busy.Kernel', =>
        @set_state('busy')
      @events.on 'kernel_disconnected.Kernel', =>
        @set_state('disconnected')

    set_state: (state) ->
      html = 'server: <strong>'+state+'</strong>'
      if state is 'busy'
        html+='<br><button id="interrupt">interrupt</button><button id="restart">restart</button>'
      @ui.attr('data-state', state).html(html)

    execute_below: =>
      @notebook.execute_cells_below()

    before_first_run: (cb) =>
      @ui.slideDown('fast')
      if @url then @start_kernel(cb)
      else @call_spawn(cb)
    
    start_kernel: (cb)=>
      @log 'start_kernel'
      @kernel = new kernel.Kernel @url+'api/kernels', '', @notebook, "python2"
      @kernel.start()
      @notebook.kernel = @kernel
      @events.on 'kernel_ready.Kernel', => 
        @has_kernel_connected = true
        @log 'kernel ready'
        for cell in @cells
          cell.set_kernel @kernel
        cb()

    start_notebook: =>
      # Stub a bunch of stuff we don't want to use
      contents = 
        list_checkpoints: -> new Promise (resolve, reject) -> resolve {}
      keyboard_manager = 
        edit_mode: ->
        command_mode: ->
        register_events: ->
        enable: ->
        disable: ->
      keyboard_manager.edit_shortcuts = handles: ->
      save_widget = 
        update_document_title: ->
        contents: ->
      config_section =  {data: {data:{}}}
      common_options = 
        ws_url: ''
        base_url: ''
        notebook_path: ''
        notebook_name: ''

      @notebook_el = $('<div id="notebook"></div>').prependTo('body')

      @notebook = new (notebook.Notebook)('div#notebook', $.extend({
        events: @events
        keyboard_manager: keyboard_manager
        save_widget: save_widget
        contents: contents
        config: config_section
      }, common_options))
  
      @notebook.kernel_selector =
        set_kernel : -> 

      @events.trigger 'app_initialized.NotebookApp'
      @notebook.load_notebook common_options.notebook_path

      @build_notebook()


    setup_ui: ->
      if $(@selector).length is 0 then return
      @ui = $('<div id="thebe_controls">').hide()
      if @options.prepend_controls_to
        @ui.prependTo(@options.prepend_controls_to)
      @ui.html('starting')

      @ui.on 'click', 'button#interrupt', (e)=>
        @log 'interrupt'
        @kernel.interrupt()
      @ui.on 'click', 'button#restart', (e)=>
        @log 'restart'
        @kernel.restart()

      # set this no matter what, else we get a warning
      window.mathjax_url = ''
      if @options.load_mathjax
        script = document.createElement("script")
        script.type = "text/javascript"
        script.src  = "http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
        document.getElementsByTagName("head")[0].appendChild(script)

      # Add some CSS links to the page
      if @options.load_css
        urls = ["https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.1.0/codemirror.css", 
                "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.11.2/jquery-ui.min.css", 
                "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.1.0/theme/base16-dark.css"]
        $.when($.each(urls, (i, url) ->
          $.get url, ->
            $('<link>',
              rel: 'stylesheet'
              type: 'text/css'
              'href': url).appendTo 'head'
        )).then => 
          # this only works correctly if caching enabled in the browser
          @log 'loaded css'

  
    log: ->
      if @debug
        console.log("%c#{[x for x in arguments]}", "color: blue; font-size: 12px");

  # This, in conjunction with height:auto in the CSS, should force CM to auto size to it's content
  codecell = require('notebook/js/codecell')
  codecell.CodeCell.options_default.cm_config.viewportMargin = Infinity

  # Auto instantiate
  $(->
      thebe = new Thebe()
  )
  return Thebe