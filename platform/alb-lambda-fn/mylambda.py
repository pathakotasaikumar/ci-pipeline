import html
import os
import pprint

def lambda_handler(event, context):

    response = {
        "statusCode": 200,
        "statusDescription": "200 OK",
        "isBase64Encoded": False,
        "headers": {
            "Content-Type": "text/html; charset=utf-8"
        }
    }

    response['body'] = """<html>
	<head>
	<title>Insert Generic Title Here!</title>
	<style>
	html, body {{
	margin: 0; padding: 0;
	font-family: arial; font-weight: 100; font-size: 1em;
	}}
	code {{
    background-color: #eee;
    border-radius: 3px;
    font-family: courier, monospace;
    padding: 0 3px;
	}}
	</style>
	</head>
	<body>
	<h1>{}</h1>
	<h2>Env</h2>
	<code>{}</code>
	<h2>Event</h2>
	<code>{}</code>
	<h2>Context</h2>
	<code>{}</code>
	</body>
	</html>""".format(html.escape(os.environ["MyText"]),
                   html.escape(pprint.pformat(os.environ)),
                   html.escape(pprint.pformat(event)),
                   html.escape(pprint.pformat(context)))
    return response
