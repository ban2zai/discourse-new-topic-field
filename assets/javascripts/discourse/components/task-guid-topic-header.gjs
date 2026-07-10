import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { modifier } from "ember-modifier";
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
  @tracked savedGuid = "";
  @tracked editing = false;
  @tracked saving = false;

  constructor(owner, args) {
    super(owner, args);
    this.savedGuid = this.topic?.task_guid || "";
    this.guid = this.savedGuid;
  }

  static shouldRender(args) {
    return (
      args.model?.can_view_task_guid || args.outletArgs?.model?.can_view_task_guid
    );
  }

  get topic() {
    return this.args.outletArgs?.model || this.args.model;
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
    return this.showStatusBadge || this.canManage;
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

  moveIntoTopicHeader = modifier((element) => {
    if (!this.shouldRenderContent) {
      return;
    }

    let frame = null;
    let placeholder = null;

    element.style.display = "none";
    element.setAttribute("aria-hidden", "true");

    if (element.parentNode) {
      placeholder = document.createComment("new-topic-field-topic-header");
      element.parentNode.insertBefore(placeholder, element);
    }

    const syncWidth = () => {
      const postFrame = document.querySelector(
        "article#post_1, .topic-post:first-of-type article.boxed, .topic-post:first-of-type .boxed"
      );
      const width = postFrame?.getBoundingClientRect().width;

      if (width) {
        element.style.setProperty(
          "--new-topic-field-topic-width",
          `${Math.round(width)}px`
        );
      }
    };

    const move = () => {
      const topicCategory = document.querySelector("#topic-title .topic-category");
      const target = topicCategory?.parentElement;

      if (!target) {
        return;
      }

      element.removeAttribute("hidden");
      element.removeAttribute("aria-hidden");
      element.style.removeProperty("display");

      if (
        element.parentElement !== target ||
        element.previousElementSibling !== topicCategory
      ) {
        topicCategory.insertAdjacentElement("afterend", element);
      }

      syncWidth();
    };

    const scheduleMove = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(move);
    };

    move();
    scheduleMove();

    const observer = new MutationObserver(scheduleMove);
    observer.observe(document.body, { childList: true, subtree: true });
    window.addEventListener("resize", scheduleMove);

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("resize", scheduleMove);

      if (placeholder?.parentNode && element.parentNode !== placeholder.parentNode) {
        placeholder.parentNode.insertBefore(element, placeholder);
      }

      placeholder?.remove();
    };
  });

  @action
  startEdit() {
    this.guid = this.savedGuid;
    this.editing = true;
  }

  @action
  cancelEdit() {
    this.guid = this.savedGuid;
    this.editing = false;
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

    this.saving = true;

    try {
      const response = await fetch(
        `/new-topic-field/topics/${this.topic.id}/guid.json`,
        {
          method: "PUT",
          credentials: "same-origin",
          headers: this.headers,
          body: JSON.stringify({ guid }),
        }
      );

      if (!response.ok) {
        if (response.status === 409) {
          this.dialog.dialog({
            type: "alert",
            message: i18n("discourse_new_topic_field.topic.duplicate_guid"),
          });
          return;
        }

        throw new Error(`GUID update failed with status ${response.status}`);
      }

      const payload = await response.json();
      this.savedGuid = payload.guid || guid;
      this.guid = this.savedGuid;
      this.editing = false;
      setTopicGuid(this.topic, this.savedGuid);
    } catch {
      this.dialog.dialog({
        type: "alert",
        message: i18n("discourse_new_topic_field.topic.save_failed"),
      });
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
    this.saving = true;

    try {
      const response = await fetch(
        `/new-topic-field/topics/${this.topic.id}/guid.json`,
        {
          method: "DELETE",
          credentials: "same-origin",
          headers: this.headers,
        }
      );

      if (!response.ok) {
        throw new Error(`GUID delete failed with status ${response.status}`);
      }

      this.savedGuid = "";
      this.guid = "";
      this.editing = false;
      setTopicGuid(this.topic, null);
    } catch {
      this.dialog.dialog({
        type: "alert",
        message: i18n("discourse_new_topic_field.topic.delete_failed"),
      });
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
    <div
      class="new-topic-field-topic-header"
      data-new-topic-field-topic-header
      hidden
      {{this.moveIntoTopicHeader}}
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
  </template>
}
