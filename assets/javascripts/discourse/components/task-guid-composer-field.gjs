import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

function queryGuid() {
  const params = new URLSearchParams(window.location.search);
  return params.get("guid")?.trim();
}

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
      this.model?.action === "createTopic" &&
      this.guid
    );
  }

  get guid() {
    return this.model?.task_guid;
  }

  syncGuidFromUrl() {
    if (!this.siteSettings.discourse_new_topic_field_enabled) {
      return;
    }

    const model = this.model;
    if (model?.action !== "createTopic" || model.task_guid) {
      return;
    }

    const guid = queryGuid();
    if (guid) {
      model.set("task_guid", guid);
    }
  }

  <template>
    {{#if this.shouldRender}}
      <div class="new-topic-field-composer" data-new-topic-field-composer>
        <div class="new-topic-field-composer__notice">
          {{i18n "discourse_new_topic_field.composer.notice"}}
        </div>

        <label class="new-topic-field-composer__label">
          <span>{{i18n "discourse_new_topic_field.guid_label"}}</span>
          <input
            type="text"
            value={{this.guid}}
            readonly
            class="new-topic-field-input"
            data-new-topic-field-composer-guid
          />
        </label>
      </div>
    {{/if}}
  </template>
}
