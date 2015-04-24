define [
  'base/js/namespace'
  'jquery'
  'thebe/dotimeout'
  'notebook/js/notebook'
  'thebe/jquery-cookie'
  'thebe/default_css'
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
], (IPython, $, doTimeout, notebook, jqueryCookie, default_css, contents, configmod, utils, page, events, actions, kernelselector, kernel, CodeMirror, custom) ->

  class Thebe
    default_options:
      # jquery selector for elements we want to make runnable 
      selector: 'pre[data-executable]'
      # the url of either a tmnb server or a notebook server
      # if it contains "spawn/", assume it's a tmpnb server
      # otherwise assume it's a notebook url
      # (default url assumes user is running tmpnb via boot2docker)
      url: '//192.168.59.103:8000/spawn/'
      # set to false to prevent kernel_controls from being added
      append_kernel_controls_to: 'body'
      # Automatically inject basic default css we need, no highlighting
      inject_css: 'no_hl'
      # Automatically load other necessary css (jquery ui)
      load_css: true
      # Automatically load mathjax js
      load_mathjax: true
      # show messages from @log()
      debug: true

    # Take our two basic configuration options
    constructor: (@options={})->
      # just for debugging
      window.thebe = this
      
      # important flags
      @has_kernel_connected = false
      @server_error = false

      # set options to defaults for unset keys
      # and break out some commonly used options
      {@selector, @url, @debug} = _.defaults(@options, @default_options)

      # if we've been given a non blank url, make sure it has a trailing slash
      if @url then @url = @url.replace(/\/?$/, '/')
      
      # if it contains /spawn, it's a tmpnb url, not a notebook url
      if @url.indexOf('/spawn') isnt -1
        @log @url+' is a tmpnb url'
        @tmpnb_url = @url
        @url = ''

      # we break the notebook's method of tracking cells, so do it ourselves
      @cells = []
      # the jupyter global event object
      @events = events
      # add some css and js dynamically, and set up some events
      @setup()
      # we only ever want the first call
      @spawn_handler = _.once(@spawn_handler)
      # Does the user already have a container running
      thebe_url = $.cookie 'thebe_url'
      # passing a notebook url takes precedence over a cookie
      if thebe_url and @url is ''
        @check_existing_container(thebe_url)
      
      # check that the tmpnb server is even up
      # before we go and add run buttons
      if @tmpnb_url
        @check_server()
      else
        @start_notebook()
    
    # CORS + redirects + are crazy, lots of things didn't work for this
    # this was from an example is on MDN
    call_spawn:(cb)=>
      @log 'call spawn'
      invo = new XMLHttpRequest
      invo.open 'GET', @tmpnb_url, true
      invo.onreadystatechange = (e)=> @spawn_handler(e, cb)
      invo.onerror = (e)=>
        @log "Cannot connect to tmpnb server", true 
        @set_state('disconnected')
        $.removeCookie 'thebe_url'
      invo.send()

    check_server: (invo=new XMLHttpRequest)->
      # Hacky, the /stats endpoint would be more appropriate, but I didn't include that in my pr
      invo.open 'GET', @tmpnb_url.replace('/spawn', '')+'user/some_fake_user/api', true
      invo.onerror = (e)=>
        @log 'Cannot connect to tmpnb server!'
        @server_error = true
        console.log e
        @start_notebook()
      invo.onload = (e)=>
        @log 'Tmpnb server seems to be up'
        @start_notebook()
      invo.send()

    check_existing_container: (url, invo=new XMLHttpRequest)->
      # no trailing slash for api url
      invo.open 'GET', url+'api', true
      invo.onerror = (e)=>
        $.removeCookie 'thebe_url'
        @log 'server error when checking existing container'
      invo.onload = (e)=>
        # if we can parse the response, it's the actual api
        try
          JSON.parse e.target.responseText
          @url = url
          @log 'cookie with notebook server url was right, use as needed'
        # otherwise it's a notebook_not_found, a page that would js redirect you to /spawn
        catch
          $.removeCookie 'thebe_url'
          @log 'cookie was wrong/outdated, call spawn as needed'
      # Actually send the request
      invo.send()

    spawn_handler: (e, cb) =>
      # is the server up?
      if e.target.status in [0, 405]
        @log 'Cannot connect to tmpnb server, status: ' + e.target.status, true
        @set_state('disconnected')
      # is it full up of active containers?
      else if e.target.responseURL.indexOf('/spawn') isnt -1
        @log 'tmpnb server full', true
        @set_state('full')
      # otherwise start the kernel
      else
        @url = e.target.responseURL.replace('/tree', '/')
        @log 'responseUrl is'
        @log e.target.responseURL
        @start_kernel(cb)
        $.cookie 'thebe_url', @url

    build_notebook: =>
      # don't even try to save or autosave
      @notebook.writable = false

      # get rid of default first cell
      # otherwise this will mess up our index
      @notebook._unsafe_delete_cell(0)

      $(@selector).each (i, el) =>
        cell = @notebook.insert_cell_at_bottom('code')
        # grab text, trim it, put it in cell
        cell.set_text $(el).text().trim()
        controls = $("<div class='thebe_controls' data-cell-id='#{i}'></div>")
        controls.html(@controls_html())
        $(el).replaceWith cell.element
        # cell.refresh()
        @cells.push cell
        unless @server_error
          $(cell.element).prepend controls
        cell.element.removeAttr('tabindex')
        # otherwise cell.js will throw an error
        cell.element.off 'dblclick'

      @notebook_el.hide()
      
      @events.on 'kernel_idle.Kernel', (e, k) =>
        @set_state('idle')
      @events.on 'kernel_busy.Kernel', =>
        @set_state('busy')
      @events.on 'kernel_disconnected.Kernel', =>
        @set_state('disconnected')

    set_state: (@state) =>
      @log 'state :'+@state
      $.doTimeout 'thebe_set_state', 500, =>
        $(".thebe_controls .state").text(@state)
        return false

    controls_html: ->
      "<button data-action='run'>run</button><span class='state'></span>"

    kernel_controls_html: ->
      "<button data-action='interrupt'>interrupt kernel</button><button data-action='restart'>restart kernel</button><span class='state'></span>"


    before_first_run: (cb) =>
      @set_state('starting...')
      if @url then @start_kernel(cb)
      else @call_spawn(cb)

      if @options.append_kernel_controls_to 
        kernel_controls = $("<div class='thebe_controls kernel_controls'></div>")
        kernel_controls.html(@kernel_controls_html()).appendTo @options.append_kernel_controls_to

    
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

    get_button_by_cell_id: (id)->
      $(".thebe_controls[data-cell-id=#{id}] button[data-action='run']")

    run_cell: (cell_id, end_id=false)=>
      cell = @cells[cell_id]
      button = @get_button_by_cell_id(cell_id)
      if not @has_kernel_connected
        @before_first_run =>
          button.text('running').addClass 'running'
          cell.execute()
          if end_id
            for cell in @cells[cell_id+1..end_id]
              cell.execute()
      else
        button.text('running').addClass 'running'
        cell.execute()
        if end_id
          for cell in @cells[cell_id+1..end_id]
            cell.execute()

    setup: =>
      # main click handler
      $('body').on 'click', 'div.thebe_controls button', (e)=>
        button = $(e.target)
        id = button.parent().data('cell-id')
        action = button.data('action')
        if e.shiftKey
          action = 'shift-'+action
        switch action
          when 'run'
            @run_cell(id)
          when 'shift-run'
            @log 'exec from top to cell #'+id
            @run_cell(0, id)
          when 'interrupt'
            @kernel.interrupt()
          when 'restart'
            if confirm('Are you sure you want to restart the kernel? Your work will be lost.')
              @kernel.restart()

      @events.on 'execute.CodeCell', (e, cell) =>
        id = $('.cell').index(cell.cell.element)
        @log 'exec done for codecell '+id
        button = @get_button_by_cell_id(id)
        button.text('done').removeClass('running').addClass('ran')

      # set this no matter what, else we get a warning
      window.mathjax_url = ''
      if @options.load_mathjax
        script = document.createElement("script")
        script.type = "text/javascript"
        script.src  = "//cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
        document.getElementsByTagName("head")[0].appendChild(script)

      # inject  default styles right into the page
      if @options.inject_css is 'no_hl'
        $("<style>#{default_css.no_hl}</style>").appendTo('head')
      else if @options.inject_css 
        $("<style>#{default_css.css}</style>").appendTo('head')

      # Add some CSS links to the page
      if @options.load_css
        urls = [
           "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.11.2/jquery-ui.min.css" 
          ]
        $.when($.each(urls, (i, url) ->
          $.get url, ->
            $('<link>',
              rel: 'stylesheet'
              type: 'text/css'
              'href': url).appendTo 'head'
        )).then => 
          # this only works correctly if caching is enabled in the browser
          # @log 'loaded css'
  
    log: (m, serious=false)->
      if @debug then console.log("%c#{m}", "color: blue; font-size: 12px");
      if serious then console.log(m)

  # So people can access it
  window.Thebe = Thebe

  # Auto instantiate it with defaults if body has data-runnable="true"
  $(->
      if $('body').data('runnable')
        thebe = new Thebe()
  )
  return {Thebe: Thebe}