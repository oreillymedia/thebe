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
  'terminal/js/terminado'
  'components/term.js/src/term'
  'codemirror/mode/ruby/ruby'
  'codemirror/mode/css/css'
  'codemirror/mode/coffeescript/coffeescript'
  'codemirror/mode/dockerfile/dockerfile'
  'codemirror/mode/go/go'
  'codemirror/mode/javascript/javascript'
  'codemirror/mode/julia/julia'
  'codemirror/mode/python/python'
  'codemirror/mode/haskell/haskell'
  'codemirror/mode/r/r'
  'codemirror/mode/shell/shell'
  'codemirror/mode/clike/clike'
  'codemirror/mode/jinja2/jinja2'
  'codemirror/mode/php/php'
  'codemirror/mode/sql/sql'
  'nbextensions/widgets/notebook/js/extension'

  'custom/custom'
], (IPython, $, promise, doTimeout, notebook, jqueryCookie, default_css, contents, configmod, utils, page, events, actions, kernelselector, kernel, CodeMirror, terminado, Terminal, custom) ->
  
  # promise.polyfill()

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
      # Default keyboard shortcut for focusing next cell, shift+ this keycode, default (32) is spacebar
      # Set to false to disable
      next_cell_shortcut: 32
      # Default keyboard shortcut for executing cell, shift+ this keycode, default (13) is return
      # Set to false to disable
      run_cell_shortcut: 13
      # For when you want a pre to become a CM instance, but not be runnable
      not_executable_selector: "pre[data-not-executable]"
      # For when you want a pre to become a CM instance, but not be writable
      read_only_selector: "pre[data-read-only]"
      # if set to false, no addendum added, if a string, use that instead
      error_addendum: true
      # adds interrupt to every cell control, when it's running
      add_interrupt_button: false
      # hack to set the codemirror mode correctly
      codemirror_mode_name: "ipython"
      # totally different mode for running a terminal instead of a notebook
      terminal_mode: false
      # where are our cell elements (that are created from the selector option above)
      container_selector: "body"
      # for setting what docker image you want to run on the back end
      image_name: "jupyter/notebook"
      # should we remember the url that we connect to
      set_url_cookie: true
      # show messages from @log()
      debug: false

    # some constants we need
    spawn_path: "api/spawn/"
    stats_path: "api/stats"
    # state constants
    start_state:     "start"
    idle_state:      "idle"
    busy_state:      "busy"
    ran_state:       "ran"
    full_state:      "full"
    cant_state:      "cant"
    disc_state:      "disconnected"
    gaveup_state:    "gaveup"
    user_error:      "user_error"
    interrupt_state: "interrupt"
    # I don't know an elegant way to use these pre instantiation
    ui: {}
    setup_constants: ->
      @error_states     = [@disc_state, @full_state, @cant_state, @gaveup_state]
      @ui[@start_state] = 'Starting server...'
      @ui[@idle_state]  = 'Run'
      @ui[@busy_state]  = 'Working <div class="thebe-spinner thebe-spinner-three-bounce"><div></div> <div></div> <div></div></div>'
      @ui[@ran_state]   = 'Run Again'
      # Button stays the same, but we add the addendum for a user error
      @ui[@user_error]  = 'Run Again'
      @ui[@interrupt_state]   = 'Interrupted. Run Again?'
      @ui[@full_state]  = 'Server is Full :-('
      @ui[@cant_state]  = 'Can\'t connect to server'
      @ui[@disc_state]  = 'Disconnected from Server<br>Attempting to reconnect'
      @ui[@gaveup_state]= 'Disconnected!<br>Click to try again'

      if @options.error_addendum is false then @ui['error_addendum']  = ""
      else if @options.error_addendum is true
        @ui['error_addendum']  = "<button data-action='run-above'>Run All Above</button> <div class='thebe-message'>It looks like there was an error. You might need to run the code examples above for this one to work.</div>"
      else @ui['error_addendum'] = @options.error_addendum 
   
    # See default_options above 
    constructor: (@options={})->
      # important flags
      @has_kernel_connected = false
      @server_error = false

      # set options to defaults if they weren't specified
      # and break out some commonly used options
      {@selector, @url, @debug} = _.defaults(@options, @default_options)

      @setup_constants()

      # if we've been given a non blank url, make sure it has a trailing slash
      if @url then @url = @url.replace(/\/?$/, '/')
      # if we have a protocol relative url, add the current protocol
      if @url[0..1] is '//' then @url=window.location.protocol+@url
      
      if @options.tmpnb_mode
        @log 'Thebe is in tmpnb mode'
        @tmpnb_url = @url
        # we will still need the actual url of our notebook server, so
        @url = ''

      # we break the notebook's method of tracking cells, so let's do it ourselves
      @cells = []
      # the jupyter global event object, jquery based, used for everything
      @events = events
      # add some css and js dynamically, and set up error handling
      @setup_resources()
      # click handlers
      @setup_user_events()
      # Does the user already have a container running
      thebe_url = $.cookie 'thebe_url'
      # passing a notebook url takes precedence over a cookie
      if thebe_url and @url is ''
        # if we're in tmpnb mode
        if @options.tmpnb_mode
          # and the tmpnb url hasn't changed
          if @tmpnb_url is thebe_url[0..@tmpnb_url.length-1]
            @check_existing_container(thebe_url)
          else $.removeCookie 'thebe_url'
        else
          @check_existing_container(thebe_url)
      
      # check that the tmpnb server is up
      if @tmpnb_url then @check_server()
      
      if not @options.terminal_mode
        # Start the notebook front end, creating cells with codemirror instances inside
        # and get everything set up for when the user hits run that first time
        @start_notebook()
      else
        if $(@selector).length isnt 1
          throw new Error "You should have one, and only one #{@selector} element in terminal mode. Change the selector option or change your html."
        @start_terminal()

    
    # NETWORKING
    # ----------------------
    #
    # CORS + redirects + are crazy, lots of things didn't work for this
    # this was from an example is on MDN
    call_spawn:(cb)=>
      @log 'call spawn'
      @track 'call_spawn'
      # this should never happen
      if @kernel?.ws then @log 'HAZ WEBSOCKET?'
      invo = new XMLHttpRequest
      invo.open 'POST', @tmpnb_url+@spawn_path, true
      payload = JSON.stringify {image_name: @options.image_name}
      invo.onreadystatechange = (e)=> 
        # if we're done, call the spawn handler
        if invo.readyState is 4 then  @spawn_handler(e, cb)
      invo.onerror = (e)=>
        @log "Cannot connect to tmpnb server", true 
        @set_state(@cant_state)
        $.removeCookie 'thebe_url'
        @track 'call_spawn_fail'
      invo.send(payload)

    check_server: (invo=new XMLHttpRequest)->
      invo.open 'GET', @tmpnb_url+@stats_path, true
      invo.onerror = (e)=>
        @track 'check_server_error'
        @log 'Checked and cannot connect to tmpnb server!'+ e.target.status, true
        # if this request completes before we add controls, this will prevent them from being added
        @server_error = true
        # otherwise, remove controls
        $('.thebe_controls').remove()
      invo.onload = (e)=>
        @log 'Tmpnb server seems to be up'
      invo.send()

    check_existing_container: (url, invo=new XMLHttpRequest)->
      @log "checking existing container", url
      # no trailing slash for api url
      invo.open 'GET', url+'api/kernels', true
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
        @set_state(@cant_state)
      else
        try
          data = JSON.parse e.target.responseText
        catch
          @log data
          @log "Couldn't parse spawn response"
          @track 'call_spawn_error'
        # is it full up of active containers?
        if data.status is 'full' 
          @log 'tmpnb server full', true
          @set_state(@full_state)
          @track 'call_spawn_full'
        # otherwise start the kernel
        else
          # Check if URL is a full URL, adapt tmpnb_url as our new URL
          fullURL = data.url.match(/(https?:\/\/.[^\/]+)(.*)/i)
          if fullURL
            @tmpnb_url = fullURL[1]
            data.url = fullURL[2]

          # concat the base url with the one we just got
          @url = @tmpnb_url+data.url+'/'
          @log 'tmpnb says we should use'
          @log @url
          if not @options.terminal_mode
            @start_kernel(cb)
          else
            @start_terminal_backend(cb)
          if @options.set_url_cookie
            $.cookie 'thebe_url', @url
          @track 'call_spawn_success'

    
    # STARTUP & DOM MANIPULATION
    # ----------------------
    #
    build_thebe: =>
      # don't even try to save or autosave
      @notebook.writable = false

      # get rid of default first cell
      # otherwise this will mess up our index
      @notebook._unsafe_delete_cell(0)

      # so that notebook.get_cells works, so widgets work
      @notebook.container = $(@options.container_selector)

      $(@selector).add(@options.not_executable_selector).each (i, el) =>
        cell = @notebook.insert_cell_at_bottom('code')
        original_id = $(el).attr('id')
        # grab text, trim it, put it in cell
        cell.set_text $(el).text().trim()
        # is this a read only cell
        if $(el).is(@options.read_only_selector)
          # not really used by the notebooks it seems, but is present in cell.js
          cell.read_only = true
          # this actually sets cm to read only mode
          cell.code_mirror.setOption("readOnly", true) # or "nocursor", though that prevents focus
        # Add run button, wrap it all up, and replace the pre's
        wrap = $("<div class='thebe_wrap'></div>")
        controls = $("<div class='thebe_controls' data-cell-id='#{i}'>#{@controls_html()}</div>")
        wrap.append cell.element.children()
        $(el).replaceWith(cell.element.empty().append(wrap))
        # cell.refresh() # not needed currently, but useful 
        @cells.push cell
        unless @server_error
          $(wrap).append controls
        # Not executable? Remove the contents of controls div
        if $(el).is(@options.not_executable_selector)
          controls.html("")

        cell.element.attr('id', original_id) if original_id
        cell.element.removeAttr('tabindex')
        # otherwise cell.js will throw an error
        cell.element.off 'dblclick'

      # We're not using the real notebook
      @notebook_el.hide()
      
      # Just to get metric on which cells are being edited
      # The flag ensures we only send once per focus, but only on edit
      focus_edit_flag = false
      # Triggered when a cell is focused on
      @events.on 'edit_mode.Cell', (e, c)=>
        focus_edit_flag = true

      # Helper for below
      get_cell_id_from_event = (e)-> $(e.currentTarget).find('.thebe_controls').data('cell-id')

      # Keyboard events
      $('div.code_cell').on 'keydown', (e)=>
        if e.which is @options.next_cell_shortcut and e.shiftKey is true
          cell_id = get_cell_id_from_event(e)
          # at the end? wrap around
          if cell_id is @cells.length-1 then cell_id = -1
          next = @cells[cell_id+1]
          next.focus_editor()
          # don't insert space or whatever
          return false
        else if e.which is @options.run_cell_shortcut and e.shiftKey is true
          cell_id = get_cell_id_from_event(e)
          @run_cell(cell_id)
          # don't insert a CR or whatever
          return false
        # finally, this is just for metrics
        else if focus_edit_flag
          cell_id = get_cell_id_from_event(e)
          @track 'cell_edit', {cell_id: cell_id} 
          focus_edit_flag = false
        # XXX otherwise code will be uneditable!
        return true
      
      # Interrupt on ctrl-c, because terminal
      $(window).on 'keydown', (e)=>
        if e.which is 67 and e.ctrlKey then @kernel.interrupt()
      
      # Used for a successful reconnection
      @events.on 'kernel_connected.Kernel', =>
        # Empty string = already connected but lost it
        if @has_kernel_connected is ''
          for cell, id in @cells
            # Reset all the buttons to run or run again
            @show_cell_state(@idle_state, id)

      @events.on 'kernel_idle.Kernel', =>
        # set idle state outside of poll, doesn't effect ui
        @set_state @idle_state
        # then poll to make sure we're still idle before changing ui
        $.doTimeout 'thebe_idle_state', 300, =>
          if @state is @idle_state
            busy_ids = $(".thebe_controls button[data-state='busy']").parent().map(->$(this).data('cell-id'))
            # just the busy ones, doesn't do it on reconnect
            for id in busy_ids
              @show_cell_state(@idle_state, id)

            # Get rid of the traceback output generated for user interrupt
            interrupt_ids = $(".thebe_controls button[data-state='interrupt']").parent().map(->$(this).data('cell-id'))
            for id in interrupt_ids
              @cells[id]["output_area"].clear_output(false)

            return false
          else if @state not in @error_states
            # keep polling
            return true
          else return false

      @events.on 'kernel_busy.Kernel', =>
        @set_state(@busy_state)

      # We use this instead of 'kernel_disconnected.Kernel'
      # because the kernel always tries to reconnect
      @events.on 'kernel_reconnecting.Kernel', (e, data)=>
        @log 'Reconnect attempt #'+ data.attempt
        if data.attempt < 5
          time = Math.pow 2, data.attempt
          @set_state(@disc_state, time)
        else
          @set_state(@gaveup_state)


      # This listens to a custom event I added in outputarea.js's handle_output function
      @events.on 'output_message.OutputArea', (e, msg_type, msg, output_area)=>
        controls = $(output_area.element).parents('.code_cell').find('.thebe_controls')
        id = controls.data('cell-id')
        if msg_type is 'error'
          # $.doTimeout 'thebe_idle_state'
          @log 'Error executing cell #'+id
          if msg.content.ename is "KeyboardInterrupt"
            @log "KeyboardInterrupt by User"
            @show_cell_state(@interrupt_state, id)
          else
            @show_cell_state(@user_error, id)

    # USER INTERFACE
    # ----------------------
    #
    # This doesn't change the html except for the error states
    # Otherwise it only sets the @state variable
    set_state: (@state, reconnect_time='') =>
      @log 'Thebe: '+@state
      if @state in @error_states
        html = @ui[@state]
        if reconnect_time then html += " in #{reconnect_time} seconds"
        $(".thebe_controls").html @controls_html(@state, html)
        
        if @state is @disc_state
          $(".thebe_controls button").prop('disabled', true)

    show_cell_state: (state, cell_id)=>
      @set_state(state)
      @log 'show cell state: '+ state + ' for '+ cell_id
      # has this cell already been run and we're switching it to idle
      if @cells[cell_id]['last_msg_id'] and state is @idle_state
        state = @ran_state
      $(".thebe_controls[data-cell-id=#{cell_id}]").html @controls_html(state)


    # Basically a template
    # Note: not @state
    controls_html: (state=@idle_state, html=false)=>
      if not html then html = @ui[state]
      result = "<button data-action='run' data-state='#{state}'>#{html}</button>"
      if @options.add_interrupt_button and state is @busy_state # and state is running??
        result+="<button data-action='interrupt'>Interrupt</button>"
      if state is @user_error
        result+=@ui["error_addendum"]
      result
    
    get_controls_html: (cell)=>
      $(cell.element).find(".thebe_controls").html()

    # Basically a template
    kernel_controls_html: ->
      "<button data-action='run-above'>Run All</button> <button data-action='interrupt'>Interrupt</button> <button data-action='restart'>Restart</button>"

    # EVENTS
    # ----------------------
    #
    # User clicks a run button, end_id is for the run above feature
    # The combo of the callback and range makes it a little awkward
    run_cell: (cell_id, end_id=false)=>
      @track 'run_cell', {cell_id: cell_id, end_id: end_id}
      
      # This deals with when we allow a user to try to call spawn again after a disconnect
      # A bit confusing, because @error_states contains gaveup and cant
      # but we don't want it to count in this special case, because we're
      # starting over after a disconnect
      if @state in [@gaveup_state, @cant_state]
        @log 'Lets reconnect thebe to the server'
        # Reset flags, using blank string to be falsy 
        # but different from the initial value of @has_kernel_connected
        @has_kernel_connected = ''
        # and this will cause us to call_spawn
        @url = ''

      # If we're still trying to reconnect to the same url
      # or we're already starting up, just return
      else if @state in @error_states.concat(@start_state)
        @log 'Not attempting to reconnect thebe to server, state: '+ @state
        return

      # The actual run cell logic, depends on if we've already connected or not
      cell = @cells[cell_id]
      
      if not @get_controls_html(cell) then return

      if not @has_kernel_connected
        @show_cell_state(@start_state, cell_id)
        # pass the callback to before_first_run
        # which will pass it either to start_kernel or call_spawn
        @before_first_run =>
          @show_cell_state(@busy_state, cell_id)
          cell.execute()
          if end_id
            for cell, i in @cells[cell_id+1..end_id]
              if not @get_controls_html(cell) then continue
              @show_cell_state(@busy_state, i+1)
              cell.execute()
      # if we're already connected to the kernel
      else
        @show_cell_state(@busy_state, cell_id)
        cell.execute()
        if end_id
          for cell, i in @cells[cell_id+1..end_id]
            if not @get_controls_html(cell) then continue
            @show_cell_state(@busy_state, i+1)
            cell.execute()

    # Note, we don't call the callback here, just pass it on
    before_first_run: (cb) =>
      if @url then @start_kernel(cb)
      else @call_spawn(cb)

      if @options.append_kernel_controls_to and not $('.kernel_controls').length
        kernel_controls = $("<div class='kernel_controls'></div>")
        kernel_controls.html(@kernel_controls_html()).appendTo @options.append_kernel_controls_to

    setup_user_events: ->
      # main click handler
      $('body').on 'click', 'div.thebe_controls button, div.kernel_controls button', (e)=>
        button = $(e.currentTarget)
        id = button.parent().data('cell-id')
        action = button.data('action')
        if e.shiftKey
          action = 'shift-'+action
        switch action
          when 'run'
            @run_cell(id)
          when 'shift-run', 'run-above'
            if not id then id = @cells.length
            @log 'exec from top to cell #'+id
            @run_cell(0, id)
          when 'interrupt'
            @kernel.interrupt()
          when 'restart'
            if confirm('Are you sure you want to restart the kernel? Your work will be lost.')
              @kernel.restart()

    start_kernel: (cb)=>
      @log 'start_kernel with '+@url
      @kernel = new kernel.Kernel @url+'api/kernels', '', @notebook, @options.kernel_name
      # hack to fix changes in v4 in kernel selector, this was an object instead
      @kernel.name = @options.kernel_name
      # start it
      @kernel.start()
      @notebook.kernel = @kernel
      @events.on 'kernel_ready.Kernel', =>
        @has_kernel_connected = true
        @log 'kernel ready'
        for cell, i in @cells
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
      @notebook.load_notebook common_options.notebook_path, @options.codemirror_mode_name
      IPython.notebook = @notebook
      utils.load_extension('widgets/notebook/js/extension')
      # And finally
      @build_thebe()

    # equivalent to @start_notebook/build_thebe, i.e. doesn't do anything on the server
    # (but sets up call_spawn and start_terminal_backend on click, for now)
    start_terminal: =>
      $(@selector).one 'click', (e)=>
        # basically the same as before_first_run
        if @url then @start_terminal_backend()
        else @call_spawn(->)

    # equivalent to @start_kernel 
    # i.e. actually starts terminal on the server (after spawn if needed)
    start_terminal_backend: =>
      invo = new XMLHttpRequest
      invo.open "POST", @url+"api/terminals", true
      invo.onreadystatechange = (e)=> 
        if invo.readyState is 4
          @terminal_start_handler(e)
      invo.onerror = (e)=>
        @log "Cannot connect to jupyter server to start terminal", true 
        @set_state(@cant_state)
        $.removeCookie 'thebe_url'
        @track 'start_terminal_fail'
      invo.send()


    terminal_start_handler: (e)->
      res = JSON.parse e.target.responseText
      terminal_name = res["name"]
      ws_url = @url.replace('http', 'ws')+"terminals/websocket/#{terminal_name}"
      @log "Thebe is in terminal mode, i.e. not running as a notebook", true
      
      # remove any content in our element
      $(@selector).html("")

      # The below is copeied from terminal/main.js
      # with some changes because we want to contain the terminal
      # in al element, not the whole page
      @setup_dummy_term_div()
      # Test size: 25x80
      termRowHeight = ->  1.00 * $('#dummy-screen')[0].offsetHeight / 25
      #  # 1.02 here arrived at by trial and error to make the spacing look right
      termColWidth = ->   1.02 * $('#dummy-screen-rows')[0].offsetWidth / 80

      calculate_size = =>
        height = $(@selector).height()
        width = $(@selector).width()
        rows = Math.min(1000, Math.max(20, Math.floor(height / termRowHeight()) )) # was also - 1, but that seemed to be a line short
        cols = Math.min(1000, Math.max(40, Math.floor(width / termColWidth()) - 1))
        {rows: rows, cols: cols}

      size = calculate_size()
      # start it up
      terminal = terminado.make_terminal($(@selector)[0], size, ws_url)

      window.onresize = =>
        geom = calculate_size()
        terminal.term.resize geom.cols, geom.rows
        terminal.socket.send JSON.stringify([
          'set_size', geom.rows, geom.cols, $(@selector).height(), $(@selector).width()
        ])

    setup_dummy_term_div: ->
      fake = '<div style="position:absolute; left:-1000em">\n<pre id="dummy-screen" style="border: solid 5px white;" class="terminal">0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n0\n1\n2\n3\n<span id="dummy-screen-rows" style="">01234567890123456789012345678901234567890123456789012345678901234567890123456789</span>\n</pre>\n</div>'
      $("body").append fake

    # Sets up css loading and injection, and ajax error handling
    setup_resources: =>
      # set this no matter what, else we get a warning
      window.mathjax_url = ''
      # add the script tag to the page
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
        ))
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
      if @debug
        if not serious then console.log(m);
        else console.log("%c#{m}", "color: blue; font-size: 12px");
      else if serious then console.log(m)

    track: (name, data={})=>
      data['name'] = name
      data['kernel'] = @options.kernel_name
      if @server_error then data['server_error'] = true
      if @has_kernel_connected then data['has_kernel_connected'] = true
      $(window.document).trigger 'thebe_tracking_event', data

  # So people can access it
  window.Thebe = Thebe

  # Auto instantiate it with defaults if body has data-runnable="true"
  $(->
      if $('body').data('runnable')
        thebe = new Thebe()
  )
  return {Thebe: Thebe}