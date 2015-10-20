browserify = require('browserify')
fs = require('fs')

opts =
  paths: ["static/components", 'static', 'components', 'static/components/codemirror/']
  # paths: ["static/components", 'static']
  # paths: ["./static/components", './static']
  # paths: ["./static/components/", './static', './static/components/jquery/jquery', './static/components/codemirror']


b = browserify('static/main.js', opts)
b.transform('deamdify')

b.bundle().pipe(fs.createWriteStream('bundle.js'))