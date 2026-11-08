"""Private digital-PDF extraction worker. Never publishes document content to logs."""
import base64, hmac, io, json, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pypdf import PdfReader

secret = os.environ['SUPABASE_SERVICE_ROLE_KEY']
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/extract-pdf': return self.respond(404, {'message': 'Not found'})
        if not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + secret):
            return self.respond(403, {'message': 'Access denied'})
        length = int(self.headers.get('Content-Length', '0'))
        if length <= 0 or length > 15_000_000: return self.respond(413, {'message': 'PDF maximum size is 10 MB'})
        try:
            body = json.loads(self.rfile.read(length))
            data = base64.b64decode(body['data'], validate=True)
            if len(data) > 10_485_760 or not data.startswith(b'%PDF-'): raise ValueError('Invalid or oversized PDF')
            reader = PdfReader(io.BytesIO(data), strict=False)
            if reader.is_encrypted: raise ValueError('PDF terenkripsi tidak didukung. Ekspor salinan tanpa password.')
            if len(reader.pages) > 150: raise ValueError('Maksimal 150 halaman per import.')
            text = '\n'.join(page.extract_text(extraction_mode='layout') or '' for page in reader.pages)
            if len(text.strip()) < 15: raise ValueError('PDF hasil scan tidak didukung. Gunakan PDF digital atau CSV; OCR tersedia di fase berikutnya.')
            return self.respond(200, {'text': text[:2_000_000], 'pages': len(reader.pages), 'review_required': True})
        except (ValueError, KeyError, Exception) as error:
            return self.respond(422, {'message': str(error)[:250]})
    def respond(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json'); self.send_header('Cache-Control', 'no-store'); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass

ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
