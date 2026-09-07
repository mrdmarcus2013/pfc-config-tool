import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { CopyReview, PayorCopyPanel } from "../.test-build/app/payor-copy-panel.js";
import { apiClient } from "../.test-build/api/client.js";

const response={status:"READY",state_hash:"A".repeat(64),source_pfc_guid:"SYN-PFC",billing_form_code:"837I_5010",
  source_form_template:"Home Health",source_user_template:"None",records_normalized:0,
  line_of_business:"HOME_HEALTH",records_copied:2,records_kept:1,records_removed:3,plan_records_removed:2,
  fields_copied:8,fields_removed:12,template_contexts_updated:2,
  contexts:[{pfc_guid:"SYN-PFC",plan_guid:null,label:"Payor-level settings",templates_changed:true,
    form_template_before:"Home Health",user_template_before:"Old user template"}],
  changes:[{label:"Additional setting",action:"COPY",level:"Source plan",record_type:"INTERNAL_RECORD"}]};

test("copy panel explains full destination replacement and requires preview before acceptance",()=>{
  const html=renderToStaticMarkup(React.createElement(PayorCopyPanel,{
    source:{payor_guid:"SYN-A",plan_guid:null,pfc_guid:"SYN-PFC",audit_user:"SYN-AUDIT"},
    sourceLabel:"Synthetic source",onClose(){},onApplied(){},
  }));
  assert.match(html,/Destination plan overrides will be cleared/);
  assert.match(html,/role="dialog" aria-modal="true" aria-labelledby="copy-title" tabindex="-1"/);
  assert.match(html,/Line of Business must match/);
  assert.match(html,/<button[^>]+disabled[^>]*>Accept and Copy/);
  assert.doesNotMatch(html,/SYN-AUDIT/);
  assert.match(html,/Checking eligible destination payors/);
  assert.match(html,/<select[^>]+disabled/);
  assert.doesNotMatch(html,/<option[^>]*value="SYN-B"/);
});

test("preview lists affected contexts and removals without internal record codes",()=>{
  const html=renderToStaticMarkup(React.createElement(CopyReview,{result:response,destination:"Synthetic destination"}));
  assert.match(html,/Existing settings removed/);
  assert.match(html,/Plan overrides included in removals/);
  assert.match(html,/Adopt source templates/);
  assert.match(html,/Old user template/);
  assert.match(html,/None/);
  assert.doesNotMatch(html,/INTERNAL_RECORD|SYN-PFC/);
});

test("copy endpoints send source plan, destination payor and exact preview hash",async()=>{
  const original=globalThis.fetch;const calls=[];
  globalThis.fetch=async(url,init)=>{calls.push([url,JSON.parse(init.body)]);return new Response(JSON.stringify(response),{status:200});};
  try {
    const request={source_payor_guid:"SYN-A",source_plan_guid:"SYN-PLAN",destination_payor_guid:"SYN-B",audit_user:"SYN-AUDIT"};
    await apiClient.previewPayorCopy(request);
    await apiClient.applyPayorCopy({...request,expected_state_hash:response.state_hash});
    assert.equal(calls[0][0],"/api/payor-copy/preview");
    assert.equal(calls[1][0],"/api/payor-copy/apply");
    assert.equal(calls[1][1].expected_state_hash,response.state_hash);
    assert.equal(calls[1][1].source_plan_guid,"SYN-PLAN");
    assert.ok(!("destination_plan_guid" in calls[1][1]));
    const {destination_payor_guid, ...source}=request;
    await apiClient.eligibleCopyDestinations(source);
    assert.equal(calls[2][0],"/api/payor-copy/destinations");
    assert.deepEqual(calls[2][1],source);
  } finally {globalThis.fetch=original;}
});
