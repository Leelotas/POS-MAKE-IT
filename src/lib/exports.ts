import type {Snapshot} from './types';
import Decimal from 'decimal.js';
import {report,summaryRows,thaiDate} from './reports';
function tables(data:Snapshot,from:string,to:string){
 const r=report(data,from,to);
 const bill=(id:string)=>data.sales.find(s=>s.id===id)?.bill_no??id;
 return [
 {name:'สรุป',headers:['รายการ','จำนวน / บาท'],rows:summaryRows(r)},
 {name:'รายการขาย',headers:['เลขบิล','วันที่เวลา','ชำระโดย','ยอดขาย','ต้นทุน','สถานะ','เหตุผลยกเลิก'],rows:r.sales.map(s=>[s.bill_no,thaiDate(s.created_at),s.payment==='cash'?'เงินสด':'เงินโอน',Number(s.total),Number(s.cost),s.voided_at?'ยกเลิก':'สำเร็จ',s.void_reason??''])},
 {name:'สินค้าในบิล',headers:['เลขบิล','สินค้า','จำนวน','ราคาต่อหน่วย','ต้นทุนต่อหน่วย','รวม','สถานะ'],rows:data.items.filter(i=>r.sales.some(s=>s.id===i.sale_id)).map(i=>[bill(i.sale_id),i.name,i.quantity,Number(i.price),Number(i.cost),new Decimal(i.price).times(i.quantity).toNumber(),r.sales.find(s=>s.id===i.sale_id)?.voided_at?'ยกเลิก':'สำเร็จ'])},
 {name:'รายรับรายจ่าย',headers:['วันที่เวลา','ประเภท','หมวดหมู่','จำนวนเงิน','หมายเหตุ'],rows:r.entries.map(e=>[thaiDate(e.occurred_at),{income:'รายรับ',expense:'รายจ่าย',purchase:'ซื้อสินค้า'}[e.kind],e.category,Number(e.amount),e.note])},
 {name:'สต็อกปัจจุบัน',headers:['สินค้า','หมวดหมู่','คงเหลือ','ราคาขาย','ต้นทุนเฉลี่ย','สถานะ'],rows:data.products.map(p=>[p.name,p.category,p.stock,Number(p.price),Number(p.average_cost),p.active?'เปิดขาย':'ปิดขาย'])},
 ];
}
export async function exportExcel(data:Snapshot,from:string,to:string){
 const ExcelJS=await import('exceljs');const workbook=new ExcelJS.Workbook();
 workbook.creator='MAKE IT';workbook.created=new Date();
 for(const table of tables(data,from,to)){
  const sheet=workbook.addWorksheet(table.name);
  sheet.addRow([data.shop?.name??'MAKE IT',`${from} — ${to}`]);
  sheet.addRow(table.headers);sheet.getRow(2).font={name:'Prompt',bold:true,color:{argb:'FFFFFFFF'}};
  sheet.getRow(2).fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF165DFF'}};
  table.rows.forEach(row=>{const r=sheet.addRow(row);r.font={name:'Prompt',size:11};});sheet.getRow(1).font={name:'Prompt',bold:true,size:13};
  sheet.columns.forEach((col,index)=>{col.width=index===0?28:22;col.eachCell?.((cell,row)=>{if(row>2&&typeof cell.value==='number')cell.numFmt='#,##0.00';});});
  sheet.views=[{state:'frozen',ySplit:2}];sheet.autoFilter={from:{row:2,column:1},to:{row:2,column:table.headers.length}};
 }
 const buffer=await workbook.xlsx.writeBuffer();download(new Blob([buffer as ArrayBuffer],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),`MAKE-IT_${from}_${to}.xlsx`);
}
function download(blob:Blob,name:string){const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);}
export async function exportPDF(data:Snapshot,from:string,to:string){
 const pdfMake=(await import('pdfmake/build/pdfmake')).default;
 pdfMake.addFonts({Prompt:{normal:`${location.origin}/fonts/Prompt-Regular.ttf`,bold:`${location.origin}/fonts/Prompt-Bold.ttf`,italics:`${location.origin}/fonts/Prompt-Regular.ttf`,bolditalics:`${location.origin}/fonts/Prompt-Bold.ttf`}});
 const content:import('pdfmake/interfaces').Content[]=[{text:`MAKE IT • ${data.shop?.name}`,fontSize:20,bold:true,color:'#165dff'},{text:`รายงาน ${from} ถึง ${to}`,margin:[0,8,0,16]}];
 tables(data,from,to).forEach((t,index)=>{
  content.push({text:t.name,fontSize:14,bold:true,margin:[0,12,0,8],pageBreak:index?'before':undefined});
  const widths:(number|'*')[][]=[['*',130],[45,115,55,65,65,50,'*'],[40,'*',45,85,85,75,50],[115,55,100,80,'*'],['*',100,65,80,85,60]];
  content.push({table:{headerRows:1,widths:widths[index],body:[t.headers.map(text=>({text,bold:true,color:'#ffffff',fillColor:'#165dff'})),...t.rows.map(row=>row.map(v=>({text:typeof v==='number'?new Intl.NumberFormat('th-TH',{maximumFractionDigits:2}).format(v):String(v)})))]},layout:'lightHorizontalLines'});
 });
 content.push({text:'สต็อกเป็นยอดปัจจุบัน กำไรคาดการณ์ยังไม่หักค่าใช้จ่ายในอนาคต • บิลยกเลิกไม่รวมยอดขาย • ไม่ใช่ใบกำกับภาษี',fontSize:9,margin:[0,16,0,0]});
 await pdfMake.createPdf({content,pageSize:'A4',pageOrientation:'landscape',pageMargins:[32,32,32,40],defaultStyle:{font:'Prompt',fontSize:10},footer:(page,pages)=>({text:`MAKE IT • ${page} / ${pages}`,alignment:'center',fontSize:9,margin:[0,12,0,0]})}).download(`MAKE-IT_${from}_${to}.pdf`);
}
