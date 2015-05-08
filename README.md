`Thebe` takes the [Jupyter](https://github.com/jupyter/) (formerly [ipython](https://github.com/ipython/ipython)) front end, and make it work outside of the notebook context.

## What? Why?
In short, this is an easy way to let users on a web page run code examples on a server. 

Here are a [some](https://oreillymedia.github.io/thebe/matplotlib-3d.html) relatively simple [examples](https://oreillymedia.github.io/thebe/matplotlib.html) and a more [complicated](https://oreillymedia.github.io/thebe/built_sans_runnable_attr.html) one.

Four things are required:

1. A server, either a [tmpnb](https://github.com/zischwartz/tmpnb) server, for lots of users, or simple an [ipython notebook server](http://ipython.org/notebook.html).
1. A web page with some code examples
1. A script tag in the page that includes the compiled javascript of `Thebe`, which is in this repo at `static/main-built.js`
1. jQuery, already included in the page

Also, [Thebe is a moon of Jupiter](http://en.wikipedia.org/wiki/Thebe_%28moon%29) in case you were wondering. Naming things is hard.

## Front End Use
Include the `Thebe` script like so:

```
<script src="https://rawgit.com/oreillymedia/thebe/master/static/main-built.js" type="text/javascript" charset="utf-8"></script>
```

and then 

```
<script>
    $(function(){
        new Thebe({url:"http://some.tmpnb.server.com:8000"});
    });
</script>
```

Any `pre` tags with the `data-executable` attribute will be turned into editable, executable examples, and a run button will be added for each. Once run is clicked, `Thebe` will try to connect to the notebook server url you supplied, start the kernel, and execute the code in that example.

`shift`+`click`ing a run button will execute every preceding code example and then execute the current one.

Clicking run the first time will also add kernel controls to the bottom of the page, which will allow users to interrupt and restart the kernel. (Interrupting is equivalent to a keyboard interrupt, whereas restarting will lose all the user's variables and data.)

**Opt-in auto instantiation:** When loaded, the script will automatically start `Thebe` with the default options *if* the `body` has a `data-runnable` attribute that is set to true. 

## Options
You can override the below default options when you instantiate Thebe: `Thebe(options)`

    options:
      # jquery selector for elements we want to make runnable 
      selector: 'pre[data-executable]'
      # the url of either a tmnb server or a notebook server
      # (default url assumes user is running tmpnb via boot2docker)
      url: '//192.168.59.103:8000/'
      # is the url for tmpnb or for a notebook server
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

For example, 

    $(function(){
        var thebe = new Thebe({
          selector:"pre.cool",
          url: 'http://localhost:8888/'
        });
    });

will make each `pre` tag with class `cool` runnable, and will try to connect with an ipython notebook server running locally at the ipython notebook default address and port.

# Run Locally (Simple)
The easiest way to get this running locally is to simply set the `url` option to the url of a running ipython notebook server, as above.

After installing ipython, run it like so:

    ipython notebook  --NotebookApp.allow_origin=* --no-browser

Which defaults to running at http://localhost:8888/, and should tell you that.

## Developing the Front End
Most of the actual development takes place in `static/main.coffee`. I've tried to make as few changes to the rest of the jupyter front end as possible, but there were some cases where it was unavoidable (see #2 for more info on this).

After making a change to the javascript in `static/`, you'll need to recompile it to see your changes in `built.html` or to use it in production. `index.html` will reflect your changes that last `r.js` step.

```
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

docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN --name=proxy jupyter/configurable-http-proxy --default-target http://127.0.0.1:9999

docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN -v /var/run/docker.sock:/docker.sock zischwartz/tmpnb python orchestrate.py --image="zischwartz/scipyserver" --allow_origin="*" --command="ipython3 notebook --no-browser --port {port} --ip=* --NotebookApp.allow_origin=* --NotebookApp.base_url={base_path}" --cull-timeout=300 --cull_period=60
```

Next, start a normal server in this directory

```
python -m SimpleHTTPServer

```

and visit it at [localhost:8000](http://localhost:8000) and [localhost:8000/built.html](http://localhost:8000/built.html)


## Run This Over `https`

Run the proxy like so 

```
docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN --name=proxy zischwartz/configurable-http-proxy configurable-http-proxy --default-target=http://127.0.0.1:9999 --ssl-key=key.pem --ssl-cert=cert.pem
```

And run the tmpnb image as above/usual. Then start up a local server that supports `https`, like [this one](https://github.com/indexzero/http-server) with the `-S` option.
