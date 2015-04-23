({
    baseUrl: ".",
    paths: {
        underscore : 'components/underscore/underscore-min',
        backbone : 'components/backbone/backbone-min',
        jquery: 'components/jquery/jquery.min',
        bootstrap: 'components/bootstrap/js/bootstrap.min',
        // bootstraptour: 'components/bootstrap-tour/build/js/bootstrap-tour.min',
        jqueryui: 'components/jquery-ui/ui/minified/jquery-ui.min',
        moment: 'components/moment/moment',
        codemirror: 'components/codemirror',
        termjs: 'components/term.js/src/term',
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
    optimize: "none"//'uglify2',
})


