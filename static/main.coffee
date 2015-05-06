define [
  'base/js/namespace'
  'jquery'
  'components/es6-promise/promise.min'
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
], (IPython, $, promise, doTimeout, notebook, jqueryCookie, default_css, contents, configmod, utils, page, events, actions, kernelselector, kernel, CodeMirror, custom) ->
  
  promise.polyfill()

  class Thebe
    default_options:
      # jquery selector for elements we want to make runnable 
      selector: 'pre[data-executable]'
      # the url of either a tmnb server or a notebook server
      # (default url assumes user is running tmpnb via boot2docker)
      url: '//192.168.59.103:8000/'
      # is the url for tmpnb or for a notebook
      tmpnb_mode: true
      # the kernel name to use, must exist on notebook server
      kernel_name: "python2"
      # set to false to prevent kernel_controls from being added
      append_kernel_controls_to: false
      # Automatically inject basic default css we need, no highlighting
      inject_css: true
      # Automatically load other necessary css (jquery ui)
      load_css: true
      # Automatically load mathjax js
      load_mathjax: true
      # show messages from @log()
      debug: false

    # some constants we need
    spawn_path: "api/spawn/"
    stats_path: "stats"
    # state constants
    start_state: "start"
    idle_state:  "idle"
    busy_state:  "busy"
    ran_state:   "ran"
    full_state:  "full"
    disc_state:  "disconnected"
    error_state: "user_error"
    # I don't know an elegant way to use these pre instantiation
    ui: {}
    setup_ui_messages: ->
      @ui[@start_state] = 'Starting server...'
      @ui[@idle_state]  = 'Run'
      @ui[@busy_state]  = 'Working <div class="thebe-spinner thebe-spinner-three-bounce"><div></div> <div></div> <div></div></div>'
      @ui[@ran_state]   = 'Run Again'
      @ui[@error_state] = 'Run Again'
      @ui[@full_state]  = 'Server is Full :-('
      @ui[@disc_state]  = 'Disconnected from Server :-('
      @ui['error_addendum']  = "<button data-action='run_above'>Run all above</button> <div>It looks like there was an error. You might need to run the code examples above for this one to work</div>"

    # See default_options above 
    constructor: (@options={})->
      # important flags
      @has_kernel_connected = false
      @server_error = false

      # set options to defaults if they weren't specified
      # and break out some commonly used options
      {@selector, @url, @debug} = _.defaults(@options, @default_options)

      @setup_ui_messages()

      # if we've been given a non blank url, make sure it has a trailing slash
      if @url then @url = @url.replace(/\/?$/, '/')
      
      if @options.tmpnb_mode
        @log 'Thebe is in tmpnb mode'
        @tmpnb_url = @url
        # we will still need the actual url of our notebook server, so
        @url = ''

      # we break the notebook's method of tracking cells, so let's do it ourselves
      @cells = []
      # the jupyter global event object, jquery based, used for everything
      @events = events
      # add some css and js dynamically, and set up some events
      @setup()
      # we only ever want the first call
      @spawn_handler = _.once(@spawn_handler)
      # we don't want to let a user run this multiple times accidentally
      @call_spawn = _.once(@call_spawn)
      # Does the user already have a container running
      thebe_url = $.cookie 'thebe_url'
      # passing a notebook url takes precedence over a cookie
      if thebe_url and @url is ''
        @check_existing_container(thebe_url)
      
      # check that the tmpnb server is up
      if @tmpnb_url then @check_server()
      
      # Start the notebook front end, creating cells with codemirror instances inside
      # and get everything set up for when the user hits run that first time
      @start_notebook()
    
    # NETWORKING
    # ----------------------
    # CORS + redirects + are crazy, lots of things didn't work for this
    # this was from an example is on MDN
    call_spawn:(cb)=>
      # @set_state(@start_state)
      @log 'call spawn'
      invo = new XMLHttpRequest
      invo.open 'POST', @tmpnb_url+@spawn_path, true
      invo.onreadystatechange = (e)=> 
        # if we're done, call the spawn handler
        if invo.readyState is 4 then  @spawn_handler(e, cb)
      invo.onerror = (e)=>
        @log "Cannot connect to tmpnb server", true 
        @set_state(@disc_state)
        $.removeCookie 'thebe_url'
      invo.send()

    check_server: (invo=new XMLHttpRequest)->
      invo.open 'GET', @tmpnb_url+@stats_path, true
      invo.onerror = (e)=>
        @log 'Checked and cannot connect to tmpnb server!'+ e.target.status, true
        # if this request completes before we add controls, this will prevent them from being added
        @server_error = true
        # otherwise, remove controls
        $('.thebe_controls').remove()
      invo.onload = (e)=>
        @log 'Tmpnb server seems to be up'
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
      @log 'spawn handler called'
      # is the server up?
      if e.target.status in [0, 405]
        @log 'Cannot connect to tmpnb server, status: ' + e.target.status, true
        @set_state(@disc_state)
      else
        try
          data = JSON.parse e.target.responseText
        catch
          @log data
          @log "Couldn't parse spawn response"
        # is it full up of active containers?
        if data.status is 'full' 
          @log 'tmpnb server full', true
          @set_state(@full_state)
        # otherwise start the kernel
        else
          # concat the base url with the one we just got
          @url = @tmpnb_url+data.url+'/'
          @log 'tmpnb says we should use'
          @log @url
          @start_kernel(cb)
          $.cookie 'thebe_url', @url

    build_thebe: =>
      # don't even try to save or autosave
      @notebook.writable = false

      # get rid of default first cell
      # otherwise this will mess up our index
      @notebook._unsafe_delete_cell(0)

      $(@selector).each (i, el) =>
        cell = @notebook.insert_cell_at_bottom('code')
        # grab text, trim it, put it in cell
        cell.set_text $(el).text().trim()
        # Add run button
        controls = $("<div class='thebe_controls' data-cell-id='#{i}'>#{@controls_html()}</div>")
        $(el).replaceWith cell.element
        # cell.refresh()
        @cells.push cell
        unless @server_error
          $(cell.element).prepend controls
        cell.element.removeAttr('tabindex')
        # otherwise cell.js will throw an error
        cell.element.off 'dblclick'

      # We're not using the real notebook
      @notebook_el.hide()
      
      @events.on 'kernel_idle.Kernel', =>
        @set_state @idle_state
        $.doTimeout 'thebe_idle_state', 300, =>
          if @state is @idle_state
            busy_ids = $(".thebe_controls button[data-state='busy']").parent().map(->$(this).data('cell-id'))
            for id in busy_ids
              @show_cell_state(@idle_state, id)
            return false
          else if @state isnt @disc_state
            # keep polling
            return true
          else return false

      @events.on 'kernel_busy.Kernel', =>
        @set_state(@busy_state)
      @events.on 'kernel_disconnected.Kernel', =>
        @set_state(@disc_state)

      # This listens to a custom event I added in outputarea.js's handle_output function
      @events.on 'output_message.OutputArea', (e, msg_type, msg, output_area)=>
        controls = $(output_area.element).parents('.code_cell').find('.thebe_controls')
        id = controls.data('cell-id')
        if msg_type is 'error'
          console.log 'cancel'
          @show_cell_state(@error_state, id)
          # $.doTimeout 'thebe_idle_state'
          @log 'Error executing cell #'+id


    # This doesn't change the html, just sets the var
    set_state: (@state) =>
      @log 'Thebe :'+@state

    show_cell_state: (state, cell_id=false)=>
      console.log 'show cell state: '+ state + ' for '+ cell_id
      # has this cell already been run and we're switching it to idle
      if @cells[cell_id]['last_msg_id'] and state is @idle_state
        state = @ran_state
      $(".thebe_controls[data-cell-id=#{cell_id}]").html @controls_html(state)

    # Note: not @state
    controls_html: (state=@idle_state)=>
      html = @ui[state]
      result = "<button data-action='run' data-state='#{state}'>#{html}</button>"
      if state is @error_state
        result+=@ui["error_addendum"]
      result

    kernel_controls_html: ->
      "<button data-action='interrupt'>interrupt kernel</button><button data-action='restart'>restart kernel</button>"

    # User clicks a run button, end_id is for the run above feature
    # The combo of the callback and range makes it a little awkward
    run_cell: (cell_id, end_id=false)=>
      cell = @cells[cell_id]
      if not @has_kernel_connected
        @show_cell_state(@start_state, cell_id)
        # pass the callback to before_first_run
        # which will pass it either to start_kernel or call_spawn
        @before_first_run =>
          @show_cell_state(@busy_state, cell_id)
          cell.execute()
          if end_id
            for cell, i in @cells[cell_id+1..end_id]
              @show_cell_state(@busy_state, i+1)
              cell.execute()
      else
        @show_cell_state(@busy_state, cell_id)
        cell.execute()
        if end_id
          for cell, i in @cells[cell_id+1..end_id]
            @show_cell_state(@busy_state, i+1)
            cell.execute()

    before_first_run: (cb) =>
      if @url then @start_kernel(cb)
      else @call_spawn(cb)

      if @options.append_kernel_controls_to 
        kernel_controls = $("<div class='thebe_controls kernel_controls'></div>")
        kernel_controls.html(@kernel_controls_html()).appendTo @options.append_kernel_controls_to
    
    start_kernel: (cb)=>
      @log 'start_kernel'
      @kernel = new kernel.Kernel @url+'api/kernels', '', @notebook, @options.kernel_name
      @kernel.start()
      @notebook.kernel = @kernel
      @events.on 'kernel_ready.Kernel', => 
        @has_kernel_connected = true
        @log 'kernel ready'
        for cell in @cells
          cell.set_kernel @kernel
        cb()

    # This sets up the jupyter notebook frontend
    # Stubbing a bunch of stuff we don't care about and would throw errors
    start_notebook: =>
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
      # And finally
      @build_thebe()

    # Sets up click events, css loading and injection, and ajax error handling
    setup: =>
      # main click handler
      $('body').on 'click', 'div.thebe_controls button', (e)=>
        button = $(e.currentTarget)
        id = button.parent().data('cell-id')
        action = button.data('action')
        if e.shiftKey
          action = 'shift-'+action
        switch action
          when 'run'
            @run_cell(id)
          when 'shift-run', 'run_above'
            @log 'exec from top to cell #'+id
            @run_cell(0, id)
          when 'interrupt'
            @kernel.interrupt()
          when 'restart'
            if confirm('Are you sure you want to restart the kernel? Your work will be lost.')
              @kernel.restart()

      # @events.on 'execute.CodeCell', (e, cell) =>
        # id = $('.cell').index(cell.cell.element)
        # @log 'exec done for codecell '+id
        # button = @get_button_by_cell_id(id)
        # button.text('done').removeClass('running').addClass('ran')

      # set this no matter what, else we get a warning
      window.mathjax_url = ''
      if @options.load_mathjax
        script = document.createElement("script")
        script.type = "text/javascript"
        script.src  = "//cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
        document.getElementsByTagName("head")[0].appendChild(script)

      # inject default styles directly into the page
      if @options.inject_css then $("<style>#{default_css.css}</style>").appendTo('head')

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

      # Sets up global ajax error handling, which is simpler than
      # hooking into the jupyter events, especially as we don't use them
      # all as they are intended to be used
      $(document).ajaxError (event, jqxhr, settings, thrownError) =>
        # We only care about errors accessing our tmpnb or a notebook
        # not mathjax or whatever other assets
        server_url = if @options.tmpnb_mode then @tmpnb_url else @url
        if settings.url.indexOf(server_url) isnt -1
          @log "Ajax Error!"
          @set_state(@disc_state)

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