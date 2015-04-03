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

  log = ->
    console.log("%c#{[x for x in arguments]}", "color: blue; font-size: large");

  class Thebe
    # Take our two basic configuration options
    constructor: (@selector, @tmpnb_url)->
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
      invo.send()

    check_existing_container: (url, invo=new XMLHttpRequest)->
      console.log 'check_existing_container'
      # no trailing slash for api
      invo.open 'GET', url+'api', true
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
      # are we full up?
      if e.target.responseURL.indexOf('/spawn') isnt -1
        @no_vacancy(e)
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
      events.on 'kernel_idle.Kernel', (e, k) ->
        $('button.run.running').removeClass('running').text 'run'
      @notebook_el.hide()
      # events.on 'kernel_busy.Kernel' ->
      # events.on 'kernel_disconnected.Kernel' ->
    execute_below: =>
      @notebook.execute_cells_below()

    start_notebook: (base_url) ->
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

    no_vacancy: ->
      console.log 'SORRY NO VACANCY !'

    setup_ui: ->
      if $(@selector).length is 0 then return
      @ui = $('<div id="thebe_controls">').prependTo('body')
      console.log @ui


  # Auto instantiate
  $(->
      thebe = new Thebe("pre[data-executable]", 'http://192.168.59.103:8000/spawn')
      # thebe = new Thebe("pre[data-executable]", 'http://jupyter-kernel.odewahn.com:8000/spawn')
  )
  return Thebe