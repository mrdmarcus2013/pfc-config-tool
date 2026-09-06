import type { ConfigurationOwner } from "../api/types";

const LABELS = {
  PAYOR_PLAN: "Payor plan", PAYOR: "Payor", USER_TEMPLATE: "User template",
  FORM_TEMPLATE: "Form template", BILLING_FORM: "Billing form",
};

const SOURCE_STATUS = {
  PAYOR_PLAN: "Plan defined", PAYOR: "Payor defined",
  USER_TEMPLATE: "Inherited from user template",
  FORM_TEMPLATE: "Inherited from form template",
  BILLING_FORM: "Inherited from billing form code",
};

export function configurationSourceStatus(owners: ConfigurationOwner[] = []): string {
  const first = owners[0];
  if (!first) return "Unavailable";
  if (owners.every((owner) => owner.level === first.level)) return SOURCE_STATUS[first.level];
  return owners.map((owner) => `${owner.target}: ${SOURCE_STATUS[owner.level]}`).join("; ");
}

export function ConfigurationOwnerDetails({ owners = [] }: { owners?: ConfigurationOwner[] }) {
  const first = owners[0];
  const shared = first && owners.every((owner) =>
    owner.level === first.level && owner.identifier === first.identifier);
  return <div>
    <dt>Configuration level owner</dt>
    <dd>{!first ? "Unavailable" : shared
      ? <>{LABELS[first.level]}: <code>{first.identifier}</code></>
      : <>Multiple owners{owners.map((owner) => <div key={owner.target}>
          {owner.target} — {LABELS[owner.level]}: <code>{owner.identifier}</code>
        </div>)}</>}
    </dd>
  </div>;
}
