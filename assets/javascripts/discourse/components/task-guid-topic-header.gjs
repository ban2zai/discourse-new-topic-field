import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content;
}

function setTopicGuid(topic, guid) {
  if (typeof topic?.set === "function") {
    topic.set("task_guid", guid);
  } else if (topic) {
    topic.task_guid = guid;
  }
}

export default class TaskGuidTopicHeader extends Component {
  @service siteSettings;
  @service dialog;

  @tracked guid = "";
  @tracked editingTopicId = null;
  @tracked visibleGuid = null;
  @tracked visibleGuidTopicId = null;
  @tracked saving = false;

  static shouldRender(args) {
    return (
      args.model?.can_view_task_guid || args.outletArgs?.model?.can_view_task_guid
    );
  }

  get topic() {
    return this.args.outletArgs?.model || this.args.model;
  }

  get savedGuid() {
    if (this.visibleGuidTopicId === this.topic?.id) {
      return this.visibleGuid || "";
    }

    return this.topic?.task_guid || "";
  }

  get editing() {
    return this.editingTopicId === this.topic?.id;
  }

  get canManage() {
    return Boolean(this.topic?.can_manage_task_guid);
  }

  get hasGuid() {
    return Boolean(this.savedGuid?.trim());
  }

  get showEmptyStatus() {
    return this.siteSettings.discourse_new_topic_field_show_empty_status;
  }

  get showStatusBadge() {
    return this.hasGuid || this.showEmptyStatus;
  }

  get shouldRenderContent() {
    return (
      Boolean(this.topic?.can_view_task_guid) &&
      (this.showStatusBadge || this.canManage)
    );
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

  get editLabel() {
    return this.hasGuid
      ? i18n("discourse_new_topic_field.topic.edit")
      : i18n("discourse_new_topic_field.topic.add");
  }

  get saveLabel() {
    return this.saving
      ? i18n("discourse_new_topic_field.topic.saving")
      : i18n("discourse_new_topic_field.topic.save");
  }

  @action
  resetEditingForCurrentTopic() {
    if (
      this.visibleGuidTopicId !== null &&
      this.visibleGuidTopicId !== this.topic?.id
    ) {
      this.visibleGuid = null;
      this.visibleGuidTopicId = null;
    }

    if (
      this.editingTopicId !== null &&
      this.editingTopicId !== this.topic?.id
    ) {
      this.guid = "";
      this.editingTopicId = null;
    }
  }

  @action
  startEdit() {
    this.guid = this.savedGuid;
    this.editingTopicId = this.topic?.id;
  }

  @action
  cancelEdit() {
    this.guid = this.savedGuid;
    this.editingTopicId = null;
  }

  @action
  updateGuid(event) {
    this.guid = event.target.value;
  }

  @action
  async saveGuid() {
    const guid = this.guid.trim();
    if (!guid) {
      this.dialog.dialog({
        type: "alert",
        message: i18n("discourse_new_topic_field.errors.guid_required"),
      });
      return;
    }

    const topic = this.topic;
    this.saving = true;

    try {
      const response = await fetch(
        `/new-topic-field/topics/${topic.id}/guid.json`,
        {
          method: "PUT",
          credentials: "same-origin",
          headers: this.headers,
          body: JSON.stringify({ guid }),
        }
      );

      if (!response.ok) {
        if (response.status === 409) {
          if (this.topic?.id === topic.id) {
            this.dialog.dialog({
              type: "alert",
              message: i18n("discourse_new_topic_field.topic.duplicate_guid"),
            });
          }
          return;
        }

        throw new Error(`GUID update failed with status ${response.status}`);
      }

      const payload = await response.json();
      const savedGuid = payload.guid || guid;
      setTopicGuid(topic, savedGuid);

      if (this.topic?.id === topic.id) {
        this.visibleGuid = savedGuid;
        this.visibleGuidTopicId = topic.id;
        this.guid = savedGuid;
        this.editingTopicId = null;
      }
    } catch {
      if (this.topic?.id === topic.id) {
        this.dialog.dialog({
          type: "alert",
          message: i18n("discourse_new_topic_field.topic.save_failed"),
        });
      }
    } finally {
      this.saving = false;
    }
  }

  @action
  deleteGuid() {
    if (window.confirm(i18n("discourse_new_topic_field.topic.delete_confirm"))) {
      this.destroyGuid();
    }
  }

  async destroyGuid() {
    const topic = this.topic;
    this.saving = true;

    try {
      const response = await fetch(
        `/new-topic-field/topics/${topic.id}/guid.json`,
        {
          method: "DELETE",
          credentials: "same-origin",
          headers: this.headers,
        }
      );

      if (!response.ok) {
        throw new Error(`GUID delete failed with status ${response.status}`);
      }

      setTopicGuid(topic, null);

      if (this.topic?.id === topic.id) {
        this.visibleGuid = "";
        this.visibleGuidTopicId = topic.id;
        this.guid = "";
        this.editingTopicId = null;
      }
    } catch {
      if (this.topic?.id === topic.id) {
        this.dialog.dialog({
          type: "alert",
          message: i18n("discourse_new_topic_field.topic.delete_failed"),
        });
      }
    } finally {
      this.saving = false;
    }
  }

  get headers() {
    const headers = {
      Accept: "application/json",
      "Content-Type": "application/json",
    };
    const token = csrfToken();

    if (token) {
      headers["X-CSRF-Token"] = token;
    }

    return headers;
  }

  <template>
    {{#if this.shouldRenderContent}}
      <div
        class="new-topic-field-topic-header"
        data-new-topic-field-topic-header
        {{didUpdate this.resetEditingForCurrentTopic this.topic.id}}
        {{willDestroy this.resetEditingForCurrentTopic}}
      >
        {{#if this.showStatusBadge}}
          <div class={{this.badgeClasses}}>
            <div class="new-topic-field-status-badge__content">
              <div class="new-topic-field-status-badge__label">
                {{this.badgeLabel}}
              </div>

              {{#if this.hasGuid}}
                <div class="new-topic-field-status-badge__guid">
                  {{this.savedGuid}}
                </div>
              {{/if}}
            </div>

            {{#if this.canManage}}
              {{#unless this.editing}}
                <button
                  type="button"
                  class="btn btn-default btn-small new-topic-field-status-badge__action"
                  disabled={{this.saving}}
                  {{on "click" this.startEdit}}
                >
                  {{this.editLabel}}
                </button>
              {{/unless}}
            {{/if}}
          </div>
        {{else}}
          {{#if this.canManage}}
            {{#unless this.editing}}
              <button
                type="button"
                class="btn btn-default btn-small new-topic-field-topic-header__button"
                data-new-topic-field-add-guid
                disabled={{this.saving}}
                {{on "click" this.startEdit}}
              >
                {{i18n "discourse_new_topic_field.topic.add"}}
              </button>
            {{/unless}}
          {{/if}}
        {{/if}}

        {{#if this.canManage}}
          {{#if this.editing}}
            <div class="new-topic-field-topic-header__editor">
              <label class="new-topic-field-topic-header__field">
                <span>{{i18n "discourse_new_topic_field.guid_label"}}</span>
                <input
                  type="text"
                  value={{this.guid}}
                  class="new-topic-field-input"
                  data-new-topic-field-topic-guid
                  {{on "input" this.updateGuid}}
                />
              </label>

              <div class="new-topic-field-topic-header__editor-actions">
                <button
                  type="button"
                  class="btn btn-primary new-topic-field-topic-header__button"
                  disabled={{this.saving}}
                  {{on "click" this.saveGuid}}
                >
                  {{this.saveLabel}}
                </button>

                <button
                  type="button"
                  class="btn btn-flat new-topic-field-topic-header__button"
                  disabled={{this.saving}}
                  {{on "click" this.cancelEdit}}
                >
                  {{i18n "discourse_new_topic_field.topic.cancel"}}
                </button>

                {{#if this.hasGuid}}
                  <button
                    type="button"
                    class="btn btn-danger new-topic-field-topic-header__button"
                    disabled={{this.saving}}
                    {{on "click" this.deleteGuid}}
                  >
                    {{i18n "discourse_new_topic_field.topic.delete"}}
                  </button>
                {{/if}}
              </div>
            </div>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
