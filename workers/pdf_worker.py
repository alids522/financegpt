"""Private digital-PDF extraction worker. Never publishes document content to logs."""
import base64, hmac, io, json, os, csv, datetime, threading, time, urllib.request, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pypdf import PdfReader
from reportlab.platypus import SimpleDocTemplate,Table,TableStyle,Paragraph,Spacer
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from html import escape

secret = os.environ['SUPABASE_SERVICE_ROLE_KEY']
supabase=os.environ.get('SUPABASE_URL','http://kong:8000')
pdfmetrics.registerFont(TTFont('Inter','/app/Inter.ttf'))
def api(path,body=None,method='GET',content_type='application/json'):
    payload=body if isinstance(body,bytes)else None if body is None else json.dumps(body).encode()
    req=urllib.request.Request(supabase+path,data=payload,method=method,headers={'apikey':secret,'Authorization':'Bearer '+secret,'Content-Type':content_type,'Accept-Profile':'financegpt','Content-Profile':'financegpt','x-upsert':'true'})
    with urllib.request.urlopen(req,timeout=45)as response:
        data=response.read()
        return json.loads(data)if data else None
def rpc(name,body):return api('/rest/v1/rpc/'+name,body,'POST')
def escaped_csv(value):
    value=''if value is None else str(value)
    if value.startswith("'"): return "'"+value
    return "'"+value if value.lstrip().startswith(('=','+','@'))or(value.lstrip().startswith('-')and not value.lstrip()[1:].isdigit())else value
def generate_report(job):
    import uuid
    from zoneinfo import ZoneInfo
    uid=job['user_id'];snapshot=job.get('filter_snapshot')or{};currency=snapshot.get('currency','IDR');dataset=job.get('type')or'transactions'
    if dataset not in ('transactions','budget','forecast'):raise ValueError('unsupported_dataset')
    query={'user_id':'eq.'+uid,'currency':'eq.'+currency,'order':'effective_at.desc,id.desc','select':'*'}
    for key in ['account_ids','category_ids','transaction_ids']:
        values=snapshot.get(key)
        if values:
            for value in values:uuid.UUID(value)
            query[{'account_ids':'account_id','category_ids':'category_id','transaction_ids':'id'}[key]]='in.('+','.join(values)+')'
    for key in ['type','status']:
        if snapshot.get(key):query[key]='eq.'+str(snapshot[key])
    profile=api('/rest/v1/profiles?user_id=eq.'+uid+'&select=timezone')[0]
    zone=ZoneInfo(profile['timezone']);now=datetime.datetime.now(zone)
    period_start=snapshot.get('start')or now.replace(day=1,hour=0,minute=0,second=0,microsecond=0).isoformat()
    period_end=snapshot.get('end')or (now.replace(day=28)+datetime.timedelta(days=4)).replace(day=1,hour=0,minute=0,second=0,microsecond=0).isoformat()
    if snapshot.get('start'):query['effective_at']='gte.'+period_start
    query_string=urllib.parse.urlencode(query)
    if snapshot.get('end'):query_string+='&effective_at='+urllib.parse.quote('lt.'+period_end)
    rows=[]
    for offset in range(0,100001,1000):
        page=api('/rest/v1/transactions?'+query_string+f'&limit=1000&offset={offset}');rows.extend(page)
        if len(page)<1000:break
    if len(rows)>100000:raise ValueError('export_too_large')
    if snapshot.get('account_ids'):rows=[x for x in rows if not x.get('destination_account_id')or x['destination_account_id']in snapshot['account_ids']]
    from decimal import Decimal
    def display_amount(value):
        exponent=0 if currency=='IDR'else 2
        return f'{Decimal(str(value)).scaleb(-exponent):,.{exponent}f}'
    account_rows=api('/rest/v1/accounts?user_id=eq.'+uid+'&select=id,name');category_rows=api('/rest/v1/categories?user_id=eq.'+uid+'&select=id,name,parent_id')
    accounts={x['id']:x['name']for x in account_rows};categories={x['id']:x['name']for x in category_rows};parents={x['id']:x['parent_id']for x in category_rows}
    def net(x):return x['amount']*(-1 if x.get('reversal_of')else 1)
    income=sum(net(x)for x in rows if x['type']=='income'and x['status']=='posted')
    expense=sum(net(x)for x in rows if x['type']=='expense'and x['status']=='posted')
    budgets=[b for b in rpc('budget_actuals',{'uid':uid})if b['currency']==currency and(not snapshot.get('account_ids')or b['account_id']in snapshot['account_ids'])and(not snapshot.get('category_ids')or b['category_id']in snapshot['category_ids'])and b['period_end']>=period_start[:10]and b['period_start']<period_end[:10]]
    # Recalculate actual from the same transaction snapshot, including split allocations.
    split_by_tx={}
    if budgets or snapshot.get('category_ids'):
        selected={x['id']for x in rows}
        for offset in range(0,100001,1000):
            splits=api('/rest/v1/transaction_splits?user_id=eq.'+uid+f'&select=transaction_id,category_id,amount&limit=1000&offset={offset}')
            for split in splits:
                if split['transaction_id']in selected:split_by_tx.setdefault(split['transaction_id'],[]).append(split)
            if len(splits)<1000:break
        if snapshot.get('category_ids'):
            rows=[x for x in rows if all(p['category_id']in snapshot['category_ids']for p in split_by_tx.get(x['id'],[]))]
            income=sum(net(x)for x in rows if x['type']=='income'and x['status']=='posted')
            expense=sum(net(x)for x in rows if x['type']=='expense'and x['status']=='posted')
        for budget in budgets:
            actual=0
            for tx in rows:
                local_day=datetime.datetime.fromisoformat(tx['effective_at']).astimezone(zone).date().isoformat()
                if tx['type']!='expense'or tx['status']!='posted'or not(budget['period_start']<=local_day<=budget['period_end'])or(budget['account_id']and tx['account_id']!=budget['account_id']):continue
                cat=budget['category_id'];parts=split_by_tx.get(tx['id'])
                amount=tx['amount']if not cat else sum(p['amount']for p in parts if p['category_id']==cat or parents.get(p['category_id'])==cat)if parts else tx['amount']if tx['category_id']==cat or parents.get(tx['category_id'])==cat else 0
                actual+=amount*(-1 if tx.get('reversal_of')else 1)
            budget['actual_minor']=actual;budget['remaining_minor']=budget['amount']-actual
    forecast=rpc('forecast_data',{'uid':uid,'period_start':period_start,'period_end':period_end,'currency_code':currency,'model':snapshot.get('method','run_rate'),'allowed_accounts':snapshot.get('account_ids',[]),'allowed_categories':snapshot.get('category_ids',[])})
    if dataset=='budget':
        fields=['budget_id','name','currency','period_start','period_end','budget_minor','actual_minor','remaining_minor']
        records=[[b['id'],b['name'],b['currency'],b['period_start'],b['period_end'],b['amount'],b['actual_minor'],b['remaining_minor']]for b in budgets]
    elif dataset=='forecast':
        fields=['currency','actual_minor','known_scheduled_minor','known_income_minor','forecast_eop_minor','budget_minor','remaining_minor','projected_variance_minor','expected_closing_cash_minor','method','model_version','confidence','generated_at']
        records=[[forecast.get(key,'')for key in fields]]
    else:
        fields=['transaction_id','date_time','type','amount','currency','account','destination_account','category','subcategory','merchant','description','tags','status','source_ref']
        records=[[x['id'],x['effective_at'],x['type'],x['amount'],x['currency'],accounts.get(x['account_id'],''),accounts.get(x.get('destination_account_id'),''),categories.get(parents.get(x.get('category_id'))or x.get('category_id'),''),categories.get(x.get('category_id'),'')if parents.get(x.get('category_id'))else'',x.get('merchant',''),x.get('description',''),'|'.join(x.get('tags')or[]),x['status'],x.get('source_ref','')]for x in rows]
    if job['format']=='csv':
        output=io.StringIO(newline='');writer=csv.writer(output);writer.writerow(fields);writer.writerows([[escaped_csv(v)for v in row]for row in records]);return ('\ufeff'+output.getvalue()).encode()
    if job['format']!='pdf':raise ValueError('unsupported_format')
    output=io.BytesIO();styles=getSampleStyleSheet()
    for style in styles.byName.values():style.fontName='Inter'
    elements=[Paragraph('FINANCE TRACKER',styles['Title']),Paragraph(escape(dataset.title()+' · '+period_start+' — '+period_end),styles['Normal']),Spacer(1,16),Paragraph(f'{currency} · Pemasukan {display_amount(income)} · Pengeluaran {display_amount(expense)} · Arus kas bersih {display_amount(income-expense)}',styles['Normal']),Spacer(1,16)]
    if dataset=='transactions':
        table=[['Tanggal','Tipe','Deskripsi','Nominal','Status']]+[[x['effective_at'][:10],x['type'],Paragraph(escape(x.get('description')or'')[:500],styles['BodyText']),display_amount(x['amount']),x['status']]for x in rows]
        t=Table(table,colWidths=[75,58,205,90,55],repeatRows=1);t.setStyle(TableStyle([('FONTNAME',(0,0),(-1,-1),'Inter'),('FONTSIZE',(0,0),(-1,-1),8),('BACKGROUND',(0,0),(-1,0),colors.HexColor('#EFF2F5')),('GRID',(0,0),(-1,-1),.3,colors.HexColor('#DFE3E8')),('VALIGN',(0,0),(-1,-1),'TOP'),('ALIGN',(3,1),(3,-1),'RIGHT'),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7)]));elements.append(t)
    elements.extend([Spacer(1,20),Paragraph('Budget vs Actual',styles['Heading2'])])
    for b in budgets:elements.append(Paragraph(escape(b['name'])+f": budget {display_amount(b['amount'])}, actual {display_amount(b['actual_minor'])}, remaining {display_amount(b['remaining_minor'])}",styles['Normal']))
    elements.extend([Spacer(1,16),Paragraph('Forecast '+escape(forecast['method'])+f": {display_amount(forecast['forecast_eop_minor'])} {currency}. Model {forecast['model_version']}; confidence {forecast['confidence']}. Generated "+escape(forecast['generated_at']),styles['Normal'])])
    for assumption in forecast['assumptions']:elements.append(Paragraph(escape(assumption),styles['Normal']))
    SimpleDocTemplate(output,leftMargin=28,rightMargin=28,topMargin=28,bottomMargin=28,title='Finance Tracker Report').build(elements);return output.getvalue()
def process_job(job_id):
    job=rpc('claim_export_job',{'job_id':job_id})
    if not job:return
    try:
        data=generate_report(job);path=job['user_id']+'/exports/'+job['id']+'.'+job['format']
        api('/storage/v1/object/financegpt-private/'+path,data,'POST','text/csv'if job['format']=='csv'else'application/pdf')
        api('/rest/v1/export_jobs?id=eq.'+job_id,{'status':'completed','output_path':path,'expires_at':(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(hours=24)).isoformat(),'error_code':None},'PATCH')
    except Exception:
        api('/rest/v1/export_jobs?id=eq.'+job_id,{'status':'pending'if job.get('attempts',0)<3 else'failed','error_code':'report_generation_failed'},'PATCH')
def maintenance():
    while True:
        try:
            rpc('maintenance_tick',{});rpc('scheduled_tick',{})
            for job in api('/rest/v1/export_jobs?status=in.(pending,approved,processing)&attempts=lt.3&limit=20'):process_job(job['id'])
            now=datetime.datetime.now(datetime.timezone.utc).isoformat()
            expired=api('/rest/v1/export_jobs?status=eq.completed&expires_at=lt.'+urllib.parse.quote(now)+'&limit=100')
            for job in expired:
                path=job.get('output_path','')
                if path.startswith(job['user_id']+'/exports/')and'..'not in path:
                    api('/storage/v1/object/financegpt-private',{'prefixes':[path]},'DELETE')
                    api('/rest/v1/export_jobs?id=eq.'+job['id'],{'status':'expired'},'PATCH')
        except Exception:pass
        time.sleep(30)
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
            pages = [page.extract_text(extraction_mode='layout') or '' for page in reader.pages]
            text = '\n'.join(pages)
            if body.get('ai_vision'):
                scans = [i for i, page in enumerate(pages) if len(page.strip()) < 15]
                if len(scans) > 8: raise ValueError('Maksimal 8 halaman scan per analisis AI. Pecah dokumen menjadi beberapa file.')
                if len(text) > 45000: raise ValueError('Teks PDF terlalu panjang untuk satu analisis AI. Pecah dokumen menjadi beberapa file.')
                images = []
                if scans:
                    import pypdfium2 as pdfium
                    pdf = pdfium.PdfDocument(data)
                    for index in scans:
                        page = pdf[index]
                        width, height = page.get_size()
                        bitmap = page.render(scale=min(1.5, 1600/max(width,height)))
                        image = bitmap.to_pil().convert('RGB')
                        image.thumbnail((1600, 1600))
                        out = io.BytesIO(); image.save(out, format='JPEG', quality=85)
                        images.append({'mime':'image/jpeg','data':base64.b64encode(out.getvalue()).decode(),'page':index+1})
                        image.close(); bitmap.close(); page.close()
                    pdf.close()
                return self.respond(200, {'text':text,'images':images,'pages':len(pages),'review_required':True})
            if len(text.strip()) < 15: raise ValueError('PDF scan memerlukan model vision di Finance AI.')
            return self.respond(200, {'text': text[:2_000_000], 'pages': len(reader.pages), 'review_required': True})
        except (ValueError, KeyError, Exception) as error:
            return self.respond(422, {'message': str(error)[:250]})
    def respond(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json'); self.send_header('Cache-Control', 'no-store'); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass

threading.Thread(target=maintenance,daemon=True).start()
ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
