import json
import tempfile
import unittest
from pathlib import Path
from reportlab.pdfgen import canvas
from .files import render_qa, package, linkedin_xlsx, past_posts, digest

class ProductionTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
  self.root=Path(self.temp.name);self.pdf=self.root/'sample.pdf'
  c=canvas.Canvas(str(self.pdf));c.drawString(50,750,'Team decisions');c.showPage();c.save()
  self.piece={'id':'fixture','revision':1,'status':'approved','approved_by':'TEST HUMAN','approved_at':'2026-01-01',
              'body':'Team decisions','language':'en','format':'carousel','slides':[{'headline':'Team decisions'}]}
 def test_render_content_and_alt(self):
  self.assertEqual(render_qa(self.pdf,self.piece,['Description'])['status'],'fail') # Helvetica not embedded
  self.piece['slides'][0]['headline']='Different content'
  self.assertFalse(render_qa(self.pdf,self.piece,['Description'])['checks']['text_match'])
  self.assertFalse(render_qa(self.pdf,self.piece,[])['checks']['alt_text'])
 def test_broken_file(self):
  self.assertEqual(render_qa(self.root/'missing',self.piece,['A'])['status'],'fail')
 def test_page_count(self):
  self.piece['slides']*=2
  self.assertFalse(render_qa(self.pdf,self.piece,['A','B'])['checks']['page_count'])
 def test_package_refuses_draft_or_changed(self):
  self.piece['status']='draft'
  with self.assertRaises(ValueError):package(self.piece,self.root)
  self.piece['status']='approved';self.piece['edited_after_approval']=True
  with self.assertRaises(ValueError):package(self.piece,self.root)
 def test_package_checksum_and_tamper(self):
  a={'content_id':'fixture','content_revision':1,'qa_status':'pass','storage_uri':str(self.pdf),'sha256':digest(self.pdf),'kind':'pdf'}
  p=package(self.piece,self.root/'packages',[a]);self.assertEqual(len(p['checksum']),64)
  self.pdf.write_bytes(b'changed')
  with self.assertRaises(ValueError):package(self.piece,self.root/'packages',[a])
 def test_xlsx(self):
  p=linkedin_xlsx(Path(__file__).resolve().parents[1]/'analytics_stripe_minions_en.xlsx')
  self.assertEqual(p['metrics']['comments'],27);self.assertNotIn('icp_conversations',p['metrics'])
 def test_past_human_flags(self):
  f=self.root/'p.json';f.write_text(json.dumps({'body':'hello','language':'en','is_exemplar':True}))
  with self.assertRaises(ValueError):past_posts(f)
  f.write_text(json.dumps({'body':'hello','language':'en'}));self.assertEqual(past_posts(f)[0]['notes'],'Imported draft; human review pending')

 def test_embedded_pdf_pass_and_he_rtl(self):
  from reportlab.pdfbase import pdfmetrics
  from reportlab.pdfbase.ttfonts import TTFont
  pdfmetrics.registerFont(TTFont('Embedded','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
  c=canvas.Canvas(str(self.pdf));c.setFont('Embedded',20);c.drawString(50,750,'Team decisions');c.showPage();c.save()
  self.assertEqual(render_qa(self.pdf,self.piece,['A'])['status'],'pass')
  self.piece.update(language='he',body='החלטות בצוות',slides=[{'headline':'החלטות בצוות'}])
  c=canvas.Canvas(str(self.pdf));c.setFont('Embedded',20);c.drawString(50,750,'החלטות בצוות'[::-1]);c.showPage();c.save()
  self.assertEqual(render_qa(self.pdf,self.piece,['תיאור'])['status'],'pass')
  c=canvas.Canvas(str(self.pdf));c.setFont('Embedded',20);c.drawString(50,750,'החלטות בצוות');c.showPage();c.save()
  self.assertFalse(render_qa(self.pdf,self.piece,['תיאור'])['checks']['rtl'])
