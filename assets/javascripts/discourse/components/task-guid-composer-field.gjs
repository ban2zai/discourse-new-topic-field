import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import { consumeTaskGuid } from "../lib/task-guid-cache";

export default class TaskGuidComposerField extends Component {
  @service siteSettings;

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
      this.model?.action === "createTopic"
    );
  }

  get guid() {
    return this.model?.task_guid;
  }

  get hasGuid() {
    return Boolean(this.guid?.trim());
  }

  get badgeClasses() {
    const stateClass = this.hasGuid
      ? "new-topic-field-status-badge--linked"
      : "new-topic-field-status-badge--unlinked";

    return `new-topic-field-status-badge ${stateClass}`;
  }

  get badgeLabel() {
    return this.hasGuid
      ? i18n("discourse_new_topic_field.status.linked")
      : i18n("discourse_new_topic_field.status.unlinked");
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
    if (taskGuid?.guid) {
      model.set("task_guid", taskGuid.guid);
      model.set("task_guid_expires", taskGuid.expires);
      model.set("task_guid_nonce", taskGuid.nonce);
      model.set("task_guid_sig", taskGuid.sig);
    }
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
