export type SlipTime={date:string;time:string;iso:string};

const thaiMonths:Record<string,number>={
 'มกราคม':1,'ม.ค':1,'มค':1,'กุมภาพันธ์':2,'ก.พ':2,'กพ':2,'มีนาคม':3,'มี.ค':3,'มีค':3,
 'เมษายน':4,'เม.ย':4,'เมย':4,'พฤษภาคม':5,'พ.ค':5,'พค':5,'มิถุนายน':6,'มิ.ย':6,'มิย':6,
 'กรกฎาคม':7,'ก.ค':7,'กค':7,'สิงหาคม':8,'ส.ค':8,'สค':8,'กันยายน':9,'ก.ย':9,'กย':9,
 'ตุลาคม':10,'ต.ค':10,'ตค':10,'พฤศจิกายน':11,'พ.ย':11,'พย':11,'ธันวาคม':12,'ธ.ค':12,'ธค':12,
};
const englishMonths:Record<string,number>={jan:1,january:1,feb:2,february:2,mar:3,march:3,apr:4,april:4,may:5,jun:6,june:6,jul:7,july:7,aug:8,august:8,sep:9,sept:9,september:9,oct:10,october:10,nov:11,november:11,dec:12,december:12};
const two=(n:number)=>String(n).padStart(2,'0');

function normalizeYear(year:number){
 if(year>=2400)return year-543;
 if(year>=100)return year;
 // Thai slips may abbreviate either 2026 as "26" or 2569 as "69".
 // Use whichever interpretation is closest to the current Gregorian year.
 const current=new Date().getFullYear(),gregorian=2000+year,buddhist=2500+year-543;
 return Math.abs(buddhist-current)<Math.abs(gregorian-current)?buddhist:gregorian;
}
function validDate(year:number,month:number,day:number){
 const d=new Date(Date.UTC(year,month-1,day));return d.getUTCFullYear()===year&&d.getUTCMonth()===month-1&&d.getUTCDate()===day;
}
function finish(year:number,month:number,day:number,hour:number,minute:number):SlipTime|null{
 year=normalizeYear(year);if(!validDate(year,month,day)||hour>23||minute>59)return null;
 const date=`${year}-${two(month)}-${two(day)}`,time=`${two(hour)}:${two(minute)}`;
 return {date,time,iso:new Date(`${date}T${time}:00+07:00`).toISOString()};
}

/** Parse the transaction date and time commonly printed on Thai bank slips. */
export function parseSlipTime(markdown:string):SlipTime|null{
 const text=markdown.replace(/[*_`#|<>]/g,' ').replace(/\s+/g,' ').trim();
 const timeMatches=[...text.matchAll(/(?:เวลา\s*)?(\d{1,2})\s*([:.])\s*(\d{2})(?!\s*[-/.]\s*\d)(?:\s*(?:น\.?|hrs?))?/gi)];
 const timeMatch=timeMatches.find(match=>match[2]===':'||/^เวลา/i.test(match[0]));
 if(!timeMatch)return null;const hour=Number(timeMatch[1]),minute=Number(timeMatch[3]);
 const iso=text.match(/\b(20\d{2}|25\d{2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})\b/);
 if(iso){const result=finish(Number(iso[1]),Number(iso[2]),Number(iso[3]),hour,minute);if(result)return result}
 const numeric=text.match(/\b(\d{1,2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{2,4})\b/);
 if(numeric){const result=finish(Number(numeric[3]),Number(numeric[2]),Number(numeric[1]),hour,minute);if(result)return result}
 const thaiPattern=new RegExp(`(\\d{1,2})\\s*(${Object.keys(thaiMonths).sort((a,b)=>b.length-a.length).map(x=>x.replace(/\./g,'\\.')).join('|')})\\.?\\s*(\\d{2,4})`,'i');
 const thai=text.match(thaiPattern);
 if(thai){const key=thai[2].replace(/\.$/,'');const result=finish(Number(thai[3]),thaiMonths[key],Number(thai[1]),hour,minute);if(result)return result}
 const english=text.match(/\b(\d{1,2})\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{2,4})\b/i);
 if(english){const result=finish(Number(english[3]),englishMonths[english[2].toLowerCase()],Number(english[1]),hour,minute);if(result)return result}
 return null;
}
