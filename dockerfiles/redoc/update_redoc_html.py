#!/usr/bin/python

from urllib2 import Request, urlopen
import urllib2
import os, sys
import ssl

def generate_jscript(lines):
    jscript = ''
    doc_count = 0
    for line in lines:
        data_list = line.split(':', 1)
        if len(data_list) == 2:
            jscript +=  "\t{{\n\t\tname: '{}',\n\t\turl: {}\n\t}},\n".format(data_list[0].replace("_", " ").title(), data_list[1])
            doc_count += 1
    return jscript, doc_count

def convert_data(link):
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)
    jscript = ''
    request = Request(link)
    try:
        response = urlopen(request, context=ssl_context)
    except IOError as e:
        print str(e)
    else:
        data = response.read()
        lines = data.split('\n')
        jscript, doc_count = generate_jscript(lines)
    return jscript, doc_count

def generate_redoc_html(jscript):
    html = """<!DOCTYPE html>
    <html>
      <head>
        <title>eGov API Docs</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body {
            margin: 0;
            padding-top: 40px;
          }

          nav {
            position: fixed;
            top: 0;
            width: 100%;
            z-index: 100;
          }
          #links_container {
              margin: 0;
              padding: 0;
          }

          #links_container li {
              display: inline-block;
              padding: 10px;
              color: white;
              cursor: pointer;
          }

          #links_container select {
              height: 35px;
              border-radius: 4px;
              font-size: 15px;
          }

        </style>
      </head>
      <body>

        <!-- Top navigation placeholder -->
        <nav>
          <ul id="links_container">
          </ul>
        </nav>

        <redoc scroll-y-offset="body > nav"></redoc>

        <script src="https://rebilly.github.io/ReDoc/releases/v1.x.x/redoc.min.js"> </script>
        <script>
          // list of APIS
          var apis = [

          """
    html += jscript
    html +=  """
            ];

        let MODULE_QUERY_PARAM_NAME = "module";

        // dynamically building navigation items
        var $selectContainer = document.getElementById('links_container');
        var $select = document.createElement("SELECT");
        $select.addEventListener('change', function(ev) {
          Redoc.init(ev.target.value);
          let params = new URLSearchParams(window.location.search);
    		  params.set(MODULE_QUERY_PARAM_NAME, ev.target[ev.target.selectedIndex].text);
		      window.location.search = params.toString();
        });
        apis.forEach(function(api) {
          var $selitem = document.createElement('option');
          $selitem.setAttribute('value', api.url);
          var $selText = document.createTextNode(api.name);
          $selitem.appendChild($selText);
          $select.appendChild($selitem);
        });
        $selectContainer.appendChild($select);

        let searchParams = new URLSearchParams(window.location.search);
        let module = searchParams.get(MODULE_QUERY_PARAM_NAME);
        if(module == null) {
          // initially render first API
          Redoc.init(apis[0].url);
        } else {
          let moduleAPI = apis.find(function(element) { return element.name == module; })
          if(moduleAPI == null) {
            Redoc.init(apis[0].url);
          } else {
            Redoc.init(moduleAPI.url);
            var opts = $select.options;
            for (var opt, j = 0; opt = opts[j].text; j++) {
              if (opt == moduleAPI.name) {
                $select.selectedIndex = j;
                break;
              }
            }
          }
        }

      </script>
    </body>
  </html> """
    return html

def write_html_file(html):
    index_file = '/usr/share/nginx/html/redoc/index.html'
    f = open(index_file, 'w')
    f.write(html)
    f.close

def main():
    if "REDOC_MANIFEST" in os.environ:
        link = os.environ["REDOC_MANIFEST"]
    else:
        link = 'https://raw.githubusercontent.com/egovernments/egov-services/master/docs/redoc_manifest.yml'
    jscript, doc_count = convert_data(link)
    if doc_count > 0:
        html = generate_redoc_html(jscript)
        write_html_file(html)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
