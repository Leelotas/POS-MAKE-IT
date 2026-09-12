import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseSlipTime} from '../src/lib/slip-time';

test('parses numeric, Buddhist and Thai month slip timestamps',()=>{
 assert.deepEqual(parseSlipTime('วันที่ 12/09/2026 เวลา 14:35 น.'),{date:'2026-09-12',time:'14:35',iso:'2026-09-12T07:35:00.000Z'});
 assert.deepEqual(parseSlipTime('โอนสำเร็จ 12 ก.ย. 2569 09:07'),{date:'2026-09-12',time:'09:07',iso:'2026-09-12T02:07:00.000Z'});
 assert.deepEqual(parseSlipTime('โอนสำเร็จ 14 ก.ย. 69 21:59'),{date:'2026-09-14',time:'21:59',iso:'2026-09-14T14:59:00.000Z'});
 assert.deepEqual(parseSlipTime('Transaction date 2026-09-08 18:20'),{date:'2026-09-08',time:'18:20',iso:'2026-09-08T11:20:00.000Z'});
 assert.deepEqual(parseSlipTime('12.09.2026 14:35'),{date:'2026-09-12',time:'14:35',iso:'2026-09-12T07:35:00.000Z'});
 assert.equal(parseSlipTime('ไม่พบวันเวลา'),null);
});
