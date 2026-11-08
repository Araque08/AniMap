"""Private JSON-lines IPC worker owned by Express; never listens on a port."""
import base64
import json
import sys
import uuid
from reconocimiento import ResNetMatcher, RecognitionError, MAX_BYTES, MODEL_ID


def serve(input_stream=sys.stdin, output_stream=sys.stdout):
    matcher = ResNetMatcher()
    queries = {}
    def write(value):
        output_stream.write(json.dumps(value, allow_nan=False) + '\n')
        output_stream.flush()
    write({'ready': True, 'model': MODEL_ID})
    while True:
        line = input_stream.readline(8 * 1024 * 1024)
        if not line: break
        if not line.endswith('\n'):
            write({'error': 'INVALID_REQUEST'})
            break
        request = {}
        try:
            request = json.loads(line)
            action = request.get('action')
            if action == 'release':
                queries.pop(request.get('queryId'), None)
                result = {'released': True}
            elif action in {'query', 'compare'}:
                encoded = request.get('image', '')
                if not isinstance(encoded, str) or len(encoded) > (MAX_BYTES + 2) // 3 * 4:
                    raise RecognitionError('INVALID_IMAGE')
                try: content = base64.b64decode(encoded, validate=True)
                except Exception: raise RecognitionError('INVALID_IMAGE') from None
                if action == 'query':
                    embedding = matcher.encode(content)
                    queries.clear()
                    key = str(uuid.uuid4()); queries[key] = embedding
                    result = {'queryId': key}
                else:
                    query = queries.get(request.get('queryId'))
                    if query is None: raise RecognitionError('QUERY_NOT_FOUND')
                    result = {'similarity': matcher.similarity(query, matcher.encode(content))}
            else: raise RecognitionError('INVALID_REQUEST')
            write({'id': request.get('id'), **result})
        except RecognitionError as error:
            write({'id': request.get('id'), 'error': error.code})
        except Exception:
            write({'id': request.get('id') if isinstance(request, dict) else None, 'error': 'MODEL_UNAVAILABLE'})


if __name__ == '__main__': serve()
