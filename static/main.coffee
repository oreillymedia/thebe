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
  'codemirror/lib/codemirror'
  'custom/custom'
], (IPython, $, notebook, cookies, contents, configmod, utils, page, events, actions, kernelselector, CodeMirror, custom) ->

  #not sure if this is required
  # codecell = require('notebook/js/codecell')
  # codecell.CodeCell.options_default.cm_config.viewportMargin = Infinity

  class Thebe
    default_options:
      selector: 'pre[data-executable]'
      tmpnb_url: 'http://192.168.59.103:8000/spawn'
      # set to false to not add controls to the page
      prepend_controls_to: 'html'


    # Take our two basic configuration options
    constructor: (@options={})->
      # set options to defaults if unset
      # and break out some commonly used options
      {@selector, @tmpnb_url} = _.defaults(@options, @default_options)
      @setup_ui()
      # the jupyter global event object
      @events = events
      thebe_url = cookies.getItem 'thebe_url'
      # we only want the first call
      @spawn_handler = _.once(@spawn_handler)
      # Does the user already have a container running?
      if thebe_url
        @check_existing_container(thebe_url)
      else
        @call_spawn()
    
    # CORS + redirects + are crazy, lots of things didn't work for this
    # this was from an example is on MDN
    call_spawn:(invo=new XMLHttpRequest)->
      invo.open 'GET', @tmpnb_url, true
      invo.onreadystatechange = @spawn_handler
      invo.onerror = => 
        @set_state('disconnected')
      invo.send()

    check_existing_container: (url, invo=new XMLHttpRequest)->
      # no trailing slash for api
      invo.open 'GET', url+'api', true

      invo.onerror = (e)=>
        @set_state('disconnected')

      invo.onload = (e)=>
        # if we can parse it, it's the actual api
        try 
          JSON.parse e.target.responseText
          @start_notebook url
        # otherwise it's a notebook_not_found, a page that would js redirect you to /spawn
        catch
          @call_spawn()
      # Actually send the request
      invo.send()

    spawn_handler: (e) =>
      # is the server up?
      if e.target.status is 0
        @set_state('disconnected')
      # is it full up of active containers?
      if e.target.responseURL.indexOf('/spawn') isnt -1
        @set_state('full')
      # otherwise start the notebook, passing our user's path
      else
        url = e.target.responseURL.replace('/tree', '/')
        @start_notebook url 
        cookies.setItem 'thebe_url', url

    kernel_ready: (x) =>
      # don't even try to save or autosave
      @notebook.writable = false
      #get rid of first defualt cell
      @notebook._unsafe_delete_cell 0

      $(@selector).each (i, el) =>
        cell = @notebook.insert_cell_at_bottom('code')
        cell.set_text $(el).text()
        button = $('<button class=\'run\'>run</button>')
        $(el).replaceWith cell.element
        $(cell.element).prepend button
        # otherwise cell.js will throw an error
        cell.element.off 'dblclick'
        # setup run button
        button.on 'click', (e) ->
          button.text('running').addClass 'running'
          cell.execute()
      # reset run button when the kernel is idle again
      events.on 'kernel_idle.Kernel', (e, k) =>
        @set_state('idle')
        $('button.run.running').removeClass('running').text 'run'
      @notebook_el.hide()
      events.on 'kernel_busy.Kernel', =>
        @set_state('busy')
      events.on 'kernel_disconnected.Kernel', =>
        @set_state('disconnected')

    set_state: (state) ->
      @ui.attr('data-state', state).html('server: <strong>'+state+'</strong>')

    execute_below: =>
      @notebook.execute_cells_below()

    start_notebook: (base_url) ->
      @set_state('idle')
      console.log 'start_notebook at:', base_url
      common_options = 
        ws_url: ''
        base_url: base_url
        notebook_path: ''
        notebook_name: ''
      config_section = new (configmod.ConfigSection)('notebook', common_options)
      config_section.load()
      common_config = new (configmod.ConfigSection)('common', common_options)
      common_config.load()
      acts = new (actions.init)
      # Stub a bunch of stuff we don't want to use
      pager = {}
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
      # yuck, needed because of smelly code in notebook.js
      contents = new (contents.Contents)(
        base_url: common_options.base_url
        common_config: common_config)
      @notebook_el = $('<div id=\'notebook\'></div>').prependTo('body')
      @notebook = new (notebook.Notebook)('div#notebook', $.extend({
        events: events
        keyboard_manager: keyboard_manager
        save_widget: save_widget
        contents: contents
        config: config_section
      }, common_options))
      kernel_selector = new (kernelselector.KernelSelector)('#kernel_logo_widget', @notebook)
      events.trigger 'app_initialized.NotebookApp'
      utils.load_extensions_from_config config_section
      utils.load_extensions_from_config common_config
      
      @notebook.load_notebook common_options.notebook_path

      events.on 'kernel_ready.Kernel', @kernel_ready

    setup_ui: ->
      if $(@selector).length is 0 then return
      @ui = $('<div id="thebe_controls">')
      if @options.prepend_controls_to
        @ui.prependTo(@options.prepend_controls_to)
      @ui.html('starting')

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
      console.log("%c#{[x for x in arguments]}", "color: blue; font-size: large");



  # Auto instantiate
  $(->
      thebe = new Thebe()
  )
  return Thebe