import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import { consumeTaskGuid } from "../lib/task-guid-cache";

async function validateSignature(guid, expires, nonce, sig) {
  const params = new URLSearchParams({ guid, expires, nonce, sig });
  const response = await fetch(
    `/new-topic-field/signature/validate.json?${params.toString()}`,
    {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
      },
    }
  );

  if (!response.ok) {
    throw new Error(`GUID signature validation failed with status ${response.status}`);
  }
}

export default class TaskGuidComposerField extends Component {
  @service siteSettings;

  @tracked invalidSignature = false;
  @tracked displayedGuid = null;

  constructor(owner, args) {
    super(owner, args);
    this.syncGuidFromUrl();
  }

  get model() {
    return this.args.outletArgs?.model;
  }

  get shouldRender() {
    return (
      this.siteSettings.discourse_new_topic_field_enabled &&
      this.model?.action === "createTopic" &&
      (this.hasGuid ||
        this.invalidSignature ||
        this.siteSettings.discourse_new_topic_field_show_empty_status)
    );
  }

  get guid() {
    return this.displayedGuid || this.model?.task_guid;
  }

  get hasGuid() {
    return Boolean(this.guid?.trim());
  }

  get badgeClasses() {
    let stateClass = "new-topic-field-status-badge--unlinked";

    if (this.invalidSignature) {
      stateClass = "new-topic-field-status-badge--invalid";
    } else if (this.hasGuid) {
      stateClass = "new-topic-field-status-badge--linked";
    }

    return `new-topic-field-status-badge ${stateClass}`;
  }

  get badgeLabel() {
    if (this.invalidSignature) {
      return i18n("discourse_new_topic_field.status.invalid");
    }

    return this.hasGuid
      ? i18n("discourse_new_topic_field.status.linked")
      : i18n("discourse_new_topic_field.status.unlinked");
  }

  setTaskGuid(model, taskGuid) {
    this.displayedGuid = taskGuid.guid;
    model.set("task_guid", taskGuid.guid);
    model.set("task_guid_expires", taskGuid.expires);
    model.set("task_guid_nonce", taskGuid.nonce);
    model.set("task_guid_sig", taskGuid.sig);
  }

  clearTaskGuid(model) {
    this.displayedGuid = null;
    model.set("task_guid", null);
    model.set("task_guid_expires", null);
    model.set("task_guid_nonce", null);
    model.set("task_guid_sig", null);
  }

  syncGuidFromUrl() {
    if (!this.siteSettings.discourse_new_topic_field_enabled) {
      return;
    }

    const model = this.model;
    if (model?.action !== "createTopic" || model.task_guid) {
      return;
    }

    const taskGuid = consumeTaskGuid();
    if (!taskGuid?.guid) {
      return;
    }

    if (!this.siteSettings.discourse_new_topic_field_require_signature) {
      this.setTaskGuid(model, taskGuid);
      return;
    }

    if (!taskGuid.expires || !taskGuid.nonce || !taskGuid.sig) {
      this.invalidSignature = true;
      this.setTaskGuid(model, taskGuid);
      return;
    }

    validateSignature(taskGuid.guid, taskGuid.expires, taskGuid.nonce, taskGuid.sig)
      .then(() => {
        this.invalidSignature = false;
        this.setTaskGuid(model, taskGuid);
      })
      .catch(() => {
        this.invalidSignature = true;
        this.setTaskGuid(model, taskGuid);
      });
  }

  <template>
    {{#if this.shouldRender}}
      <div class="new-topic-field-composer" data-new-topic-field-composer>
        <div class={{this.badgeClasses}}>
          <div class="new-topic-field-status-badge__label">
            {{this.badgeLabel}}
          </div>

          {{#if this.hasGuid}}
            <div
              class="new-topic-field-status-badge__guid"
              data-new-topic-field-composer-guid
            >
              {{this.guid}}
            </div>
          {{/if}}
        </div>
      </div>
    {{/if}}
  </template>
}
