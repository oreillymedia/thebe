require [
  'base/js/namespace'
  'jquery'
  'notebook/js/notebook'
  'orm/cookies'
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

  class Thebe
    constructor: (@selector, @tmpnb_url)->
      @events = events
      @spawn_handler = _.once(@spawn_handler)
      @call_spawn()
    
    spawn_handler: (e) =>
      console.log e.type
      @start_notebook e.target.responseURL.replace('/tree', '/')
    
    call_spawn:(invocation=new XMLHttpRequest)->
      invocation.open 'GET', @tmpnb_url, true
      invocation.onreadystatechange = @spawn_handler
      invocation.send()

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

  # Auto instantiate
  $(->
      thebe = new Thebe("pre[data-executable]", 'http://192.168.59.103:8000/spawn')
      # thebe = new Thebe("pre[data-executable]", 'http://jupyter-kernel.odewahn.com:8000/spawn')
  )
  return Thebe