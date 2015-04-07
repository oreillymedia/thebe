require [
  'base/js/namespace'
  'jquery'
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
], (IPython, $, notebook, cookies, contents, configmod, utils, page, events, actions, kernelselector, kernel, CodeMirror, custom) ->

  # We need this set, theoretically, but it seems not to be neccessary in practice
  # codecell = require('notebook/js/codecell')
  # codecell.CodeCell.options_default.cm_config.viewportMargin = Infinity
  Contents = contents.Contents

  class Thebe
    default_options:
      selector: 'pre[data-executable]'
      # TODO, make this just `url`. if it ends in spawn, it's tmpnb, if it doesn't, assume it's a notebook url
      tmpnb_url: 'http://192.168.59.103:8000/spawn'
      # set to false to not add controls to the page
      prepend_controls_to: 'html'
      load_css: true
      debug: true


    # Take our two basic configuration options
    constructor: (@options={})->
      window.thebe = this
      @has_kernel_connected = false
      @url = ''

      # we break the notebook's method of tracking cells, so do it ourselves
      @cells = []
      # set options to defaults if unset
      # and break out some commonly used options
      {@selector, @tmpnb_url, @debug} = _.defaults(@options, @default_options)
      @setup_ui()
      # the jupyter global event object
      @events = events
      thebe_url = cookies.getItem 'thebe_url'
      # we only ever want the first call
      @spawn_handler = _.once(@spawn_handler)
      
      # Does the user already have a container running?
      if thebe_url
        @check_existing_container(thebe_url)
        @log 'cookie says check existin'
      else
        @start_notebook()
        # @call_spawn()
        # @log 'spawn it'
    
    # CORS + redirects + are crazy, lots of things didn't work for this
    # this was from an example is on MDN
    call_spawn:(cb)->
      console.log 'call spawn'
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
          # @call_spawn() # get rid of this XXX
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
        @cells.push cell
        $(cell.element).prepend button
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

      if @options.load_css
        # Add some CSS links to the page
        urls = ["https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.1.0/codemirror.css", 
                "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.11.2/jquery-ui.min.css", 
                "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.1.0/theme/base16-dark.css"]
        $.when($.each(urls, (i, url) ->
          $.get url, ->
            $('<link>',
              rel: 'stylesheet'
              type: 'text/css'
              'href': url).appendTo 'head'
        ))#.then ->
  
    log: ->
      if @debug
        console.log("%c#{[x for x in arguments]}", "color: blue; font-size: 12px");



  # Auto instantiate
  $(->
      thebe = new Thebe()
  )
  return Thebe