`Thebe` takes the [Jupyter](https://github.com/jupyter/) (formerly [ipython](https://github.com/ipython/ipython)) front end, and make it work outside of the notebook context.

## What? Why?
In short, this is an easy way to let users on a web page run code examples on a server.

Here are a [some](https://oreillymedia.github.io/thebe/examples/matplotlib-3d.html) relatively simple [examples](https://oreillymedia.github.io/thebe/examples/matplotlib.html) and a more [complicated](https://oreillymedia.github.io/thebe/examples/t-sne-build.html) one.

Four things are required:

1. A server, either a [tmpnb](https://github.com/zischwartz/tmpnb) server, for lots of users, or simply an [ipython notebook server](http://ipython.org/notebook.html).
1. A web page with some code examples
1. A script tag in the page that includes the compiled javascript of `Thebe`, which is in this repo at `static/main-built.js`
1. node-js and bower to install external javascript dependencies.

To install the javascript dependencies, simply run `bower install` in the root of the repository.

Also, [Thebe is a moon of Jupiter](http://en.wikipedia.org/wiki/Thebe_%28moon%29) in case you were wondering. Naming things is hard.

## Tips and Default Shortcuts
`shift`+`return` executes the example that is currently focused 
`shift`+`space`  moves the focus to the next example
`shift`+`click`ing a run button will execute all preceding code examples as well as the current one
`ctrl`+`c` works like a keyboard interrupt (in case of infinite loops and such)

You can change the first two by passing options to Thebe when you instantiate it (see below)

## Front End Use
Currently Thebe is imported via an HTML script tag.  Since Thebe is an 
alternative Jupyter notebook front-end, the notebook server version and 
ipywidgets version of the tmpnb instance are important and must be specified.  
The following example will load Thebe for the notebook version 4.1.0 and 
ipywidgets 4.0.3:

```html
<script src="http://cdn.jupyter.org/thebe/notebook4.1.0/ipywidgets4.0.3/static/main-built.js" type="text/javascript" charset="utf-8"></script>
```

**or** for the notebook version 3.x:

```html
<script src="http://cdn.jupyter.org/thebe/notebook3.0.0/static/main-built.js" type="text/javascript" charset="utf-8"></script>
```

and then, to instantiate Thebe:

```javascript
<script>
    $(function(){
        new Thebe({url:"http://some.tmpnb.server.com:8000"});
    });
</script>
```

Any `pre` tags with the `data-executable` attribute will be turned into editable, executable examples, and a run button will be added for each. Once run is clicked, `Thebe` will try to connect to the notebook server url you supplied, start the kernel, and execute the code in that example.


If `append_kernel_controls_to` is set to a dom selector, clicking run will also add kernel controls to that element, which will allow users to interrupt and restart the kernel. (Interrupting is equivalent to a keyboard interrupt, whereas restarting will lose all the user's variables and data.)

**Opt-in auto instantiation:** When loaded, the script will automatically start `Thebe` with the default options *if* the `body` has a `data-runnable` attribute that is set to true. 

## Options
You can override the below default options when you instantiate Thebe: `Thebe(options)`

```coffee
    default_options =
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
````

For example, 

```javascript
$(function(){
    var thebe = new Thebe({
      selector:"pre.cool",
      url: 'http://localhost:8888/'
    });
});
```


will make each `pre` tag with class `cool` runnable, and will try to connect with an ipython notebook server running locally at the ipython notebook default address and port.

## Terminal Mode

Thebe now includes terminal functionality, via termjs. To run a terminal in the browser, make sure you only have one instance of the selector (which defaults to `pre[data-executable]`) and set `terminal_mode` to true. Now, clicking on the element will connect and launch a terminal.

**Terminal mode only works with the most up to date version of [jupyter notebook](https://github.com/jupyter/notebook). For now, you can run this [docker image](https://hub.docker.com/r/jupyter/notebook/) and it should work.**

## CodeMirror Language Modes
For simplicity, several codemirror language modes (i.e. syntax highlighting) are bundled with Thebe. [Here's a list of them](https://github.com/oreillymedia/thebe/blob/master/static/main.coffee#L20-L34).

# Run Locally (Simple)
The easiest way to get this running locally requires setting a few options in your Thebe declaration. 

```javascript
$(function(){
    var thebe = new Thebe({
        tmpnb_mode: false,
        url: 'http://localhost:8888/'
    });
});
```


to point to your server's address `url` option to the url of a running ipython notebook server, as above.

After installing ipython, run it like so:

    ipython notebook  --NotebookApp.allow_origin='*' --no-browser

Which defaults to running at http://localhost:8888/, and should tell you that.

## Developing the Front End
Most of the actual development takes place in `static/main.coffee`. I've tried to make as few changes to the rest of the jupyter front end as possible, but there were some cases where it was unavoidable (see #2 for more info on this).

After making a change to the javascript in `static/`, you'll need to recompile it to see your changes in `built.html` or to use it in production. `index.html` will reflect your changes that last `r.js` step.

```javascript
npm install -g requirejs
npm install -g coffee-script
coffee -cbm .
cd static
r.js -o build.js baseUrl=. name=almond include=main out=main-built.js 

```

## Run `tmpnb` Locally

First, you need docker (and boot2docker if you're on a OS X) installed. 

Pull the images. [This version](https://github.com/zischwartz/tmpnb) is a slightly different fork of the [main repo](https://github.com/jupyter/tmpnb), which adds a API route for `/spawn` ( `/api/spawn`).

```
docker pull jupyter/configurable-http-proxy
docker pull zischwartz/tmpnb 
docker pull zischwartz/scipyserver
```

Then startup the docker containers for the proxy and tmpnb like so:

```
export TOKEN=$( head -c 30 /dev/urandom | xxd -p )

docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN jupyter/configurable-http-proxy --default-target http://127.0.0.1:9999

docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN -v /var/run/docker.sock:/docker.sock zischwartz/tmpnb python orchestrate.py --image="zischwartz/scipyserver" --allow_origin="*" --command="ipython3 notebook --no-browser --port {port} --ip=* --NotebookApp.allow_origin=* --NotebookApp.base_url={base_path}" --cull-timeout=300 --cull_period=60
```

Next, start a normal server in this directory

```
python -m SimpleHTTPServer

```

Or with python3,

```
python -m http.server

```

and visit it at [localhost:8000](http://localhost:8000) and [localhost:8000/built.html](http://localhost:8000/built.html)


## Run This Over `https`

Run the proxy like so 

```
docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN zischwartz/configurable-http-proxy configurable-http-proxy --default-target=http://127.0.0.1:9999 --ssl-key=key.pem --ssl-cert=cert.pem
```

And run the tmpnb image as above/usual. Then start up a local server that supports `https`, like [this one](https://github.com/indexzero/http-server) with the `-S` option. It still won't work until you visit both the local server and the proxy address in your browser and say that you understand that the certs aren't valid and you want to proceed anyway.
