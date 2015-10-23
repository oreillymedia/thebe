({
    baseUrl: ".",
    paths: {
      underscore : 'components/underscore/underscore-min',
      backbone : 'components/backbone/backbone-min',
      // jquery: 'components/jquery/jquery.min',
      // jquery: 'empty:',
      jquery: '//ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min',
      bootstrap: 'components/bootstrap/js/bootstrap.min',
      jqueryui: '//ajax.googleapis.com/ajax/libs/jqueryui/1.11.4/jquery-ui.min',
      moment: 'components/moment/moment',
      "codemirror/lib": '//cdnjs.cloudflare.com/ajax/libs/codemirror/5.8.0',
      codemirror: '//cdnjs.cloudflare.com/ajax/libs/codemirror/5.8.0',
      termjs: 'components/term.js/src/term',
      'nbextensions/widgets': 'components/ipywidgets/ipywidgets/static',

        // 'nbextensions/widgets': 'components/ipywidgets/ipywidgets/static',
        // widgets: 'components/ipywidgets/ipywidgets/static'
        // contents: 'contents'
  },
  wrap: {
    "startFile": "wrap.start",
    "endFile": "wrap.end" 
  },
  shim: {
    underscore: {
      exports: '_'
    },
    backbone: {
      deps: ["underscore", "jquery"],
      exports: "Backbone"
    },
    bootstrap: {
      deps: ["jquery"],
      exports: "bootstrap"
    },
    jqueryui: {
      deps: ["jquery"],
      exports: "$"
    }
  },
    name: "main",
    out: "main-built.js",
    optimize: "none"
    // optimize: 'uglify2'
    // exclude: ['jquery']
})


