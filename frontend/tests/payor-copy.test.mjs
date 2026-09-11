import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { CopyReview, PayorCopyPanel } from "../.test-build/app/payor-copy-panel.js";
import { apiClient } from "../.test-build/api/client.js";

const response={status:"READY",state_hash:"A".repeat(64),source_pfc_guid:"SYN-PFC",billing_form_code:"837I_5010",
  source_form_template:"Synthetic source form",source_user_template:"Synthetic source user",records_normalized:0,
  line_of_business:"HOME_HEALTH",records_copied:2,records_kept:1,records_removed:3,plan_records_removed:2,
  fields_copied:8,fields_removed:12,template_contexts_updated:2,
  contexts:[{pfc_guid:"SYN-PFC",plan_guid:null,label:"Payor-level settings",templates_changed:true,
    form_template_before:"Synthetic old form",user_template_before:"Synthetic old user"},
    {pfc_guid:"SYN-PFC-PLAN",plan_guid:"SYN-PLAN",label:"Synthetic Blue Plan",templates_changed:true,
      form_template_before:"Synthetic plan form",user_template_before:"None"}],
  changes:[{label:"Additional setting",action:"COPY",level:"Source plan",record_type:"INTERNAL_RECORD"}]};

const withoutTechnicalDetails = html => html.replace(/<details class="technical-details">[\s\S]*?<\/details>/g, "");

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

test("copy reviews keep business effects visible and template origins only inside Tier 2 details for every status",()=>{
  for (const status of ["READY", "NO_CHANGE", "APPLIED"]) {
    const result = { ...response, status };
    const normal = renderToStaticMarkup(React.createElement(CopyReview,{result,destination:"Synthetic destination"}));
    const technical = renderToStaticMarkup(React.createElement(CopyReview,{result,destination:"Synthetic destination",supportDeveloperMode:true}));
    assert.match(normal,/Existing settings removed/);
    assert.match(normal,/Plan overrides included in removals/);
    assert.match(normal,/Synthetic Blue Plan|Payor-level settings/);
    assert.match(normal,/Additional setting/);
    assert.doesNotMatch(normal,/template|inherit|Source plan|Synthetic old|Synthetic source form|Synthetic source user/i);
    assert.doesNotMatch(normal,/INTERNAL_RECORD|SYN-PFC/);
    assert.equal(withoutTechnicalDetails(technical), normal, "Tier 2 must also keep ordinary copy content free of origin mechanics");
    assert.match(technical,/<details class="technical-details"><summary>Technical details<\/summary>/);
    assert.match(technical,/Template associations updated|Synthetic old form|Synthetic source user|Source plan/);
    assert.doesNotMatch(technical,/<details[^>]*\bopen(?:=|\s|>)/);
  }
});

test("copy source explanation is gated while both modes retain destination-wide warnings",()=>{
  for (const plan_guid of [null, "SYN-PLAN"]) {
    const props = { source:{payor_guid:"SYN-A",plan_guid,pfc_guid:"SYN-PFC",audit_user:"SYN-AUDIT"},
      sourceLabel:"Synthetic selected configuration",onClose(){},onApplied(){} };
    const normal = renderToStaticMarkup(React.createElement(PayorCopyPanel, props));
    const technical = renderToStaticMarkup(React.createElement(PayorCopyPanel, { ...props, supportDeveloperMode:true }));
    assert.doesNotMatch(normal,/template|inherit|precedence|become destination payor-level/i);
    assert.match(normal,/Destination plan overrides will be cleared/);
    assert.match(normal,/payor and all its plans/);
    assert.equal(withoutTechnicalDetails(technical), normal);
    assert.match(technical,/<details class="technical-details"><summary>Technical details<\/summary>/);
    assert.match(technical,/source template associations/);
    if (plan_guid) assert.match(technical,/Selected plan settings take precedence/);
    assert.doesNotMatch(technical,/<details[^>]*\bopen(?:=|\s|>)/);
  }
});

test("template-only replacement still explains a real configuration update in normal mode",()=>{
  for (const status of ["READY", "APPLIED"]) {
    const result = { ...response, status, records_copied:0, records_removed:0, plan_records_removed:0, changes:[] };
    const html = renderToStaticMarkup(React.createElement(CopyReview,{result,destination:"Synthetic destination"}));
    assert.match(html,/Payor\/plan configurations reviewed<\/dt><dd>2/);
    assert.match(html, status === "READY" ? /Configuration changes are required even though the individual settings already match/
      : /The destination configuration was updated/);
    assert.match(html,/Synthetic Blue Plan/);
    assert.doesNotMatch(html,/template|No changes are needed/i);
  }
});

test("unknown future configuration levels are excluded from ordinary review content",()=>{
  const result = { ...response, changes:[{ ...response.changes[0], level:"User template" }] };
  const normal = renderToStaticMarkup(React.createElement(CopyReview,{result,destination:"Synthetic destination"}));
  const technical = renderToStaticMarkup(React.createElement(CopyReview,{result,destination:"Synthetic destination",supportDeveloperMode:true}));
  assert.doesNotMatch(normal,/User template/);
  assert.match(technical,/User template/);
  assert.equal(withoutTechnicalDetails(technical),normal);
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
