import EmberObject from "@ember/object";
import {
  click,
  fillIn,
  render,
  settled,
  waitUntil,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import TaskGuidTopicHeader from "discourse/plugins/discourse-new-topic-field/discourse/components/task-guid-topic-header";

const TopicAbovePostsFixture = <template>
  <div class="container posts">
    <div class="row">
      <section class="topic-area">
        <div class="posts-wrapper">
          <span>
            <TaskGuidTopicHeader @model={{@topic}} />
          </span>
        </div>
      </section>
    </div>
  </div>
</template>;

function buildTopic({
  id,
  guid,
  canView = true,
  canManage = true,
}) {
  return EmberObject.create({
    id,
    task_guid: guid,
    can_view_task_guid: canView,
    can_manage_task_guid: canManage,
  });
}

function deferredResponse() {
  let resolvePromise;
  const promise = new Promise((resolve) => {
    resolvePromise = resolve;
  });

  return {
    promise,
    resolve(payload = {}) {
      resolvePromise({
        ok: true,
        status: 200,
        json: async () => payload,
      });
    },
  };
}

module("Integration | Component | task-guid-topic-header", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.originalFetch = window.fetch;
    this.originalConfirm = window.confirm;
    this.dialog = this.owner.lookup("service:dialog");
    this.originalDialog = this.dialog.dialog;
    this.siteSettings = this.owner.lookup("service:site-settings");
    this.originalShowEmptyStatus =
      this.siteSettings.discourse_new_topic_field_show_empty_status;
    this.siteSettings.discourse_new_topic_field_show_empty_status = false;
  });

  hooks.afterEach(function () {
    window.fetch = this.originalFetch;
    window.confirm = this.originalConfirm;
    this.dialog.dialog = this.originalDialog;
    this.siteSettings.discourse_new_topic_field_show_empty_status =
      this.originalShowEmptyStatus;
  });

  test("keeps outlet ownership and updates content when the topic changes", async function (assert) {
    const topicA = buildTopic({ id: 1, guid: "guid-a" });
    const topicB = buildTopic({ id: 2, guid: "guid-b" });
    const emptyTopic = buildTopic({
      id: 3,
      guid: null,
      canManage: false,
    });
    const hiddenTopic = buildTopic({
      id: 4,
      guid: null,
      canView: false,
      canManage: false,
    });

    this.set("topic", topicA);

    await render(
      <template><TopicAbovePostsFixture @topic={{this.topic}} /></template>
    );

    assert.strictEqual(
      document.querySelectorAll("[data-new-topic-field-topic-header]").length,
      1,
      "renders one header"
    );
    assert.strictEqual(
      document.querySelector("[data-new-topic-field-topic-header]")
        .parentElement,
      document.querySelector(".posts-wrapper > span"),
      "keeps the component inside the official outlet parent"
    );
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-a");

    await click(".new-topic-field-status-badge__action");
    await fillIn("[data-new-topic-field-topic-guid]", "draft-for-topic-a");

    this.set("topic", topicB);
    await settled();

    assert.dom(".new-topic-field-topic-header__editor").doesNotExist();
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-b");
    assert.strictEqual(
      document.querySelectorAll("[data-new-topic-field-topic-header]").length,
      1,
      "does not duplicate the header after navigation"
    );

    this.set("topic", emptyTopic);
    await settled();
    assert.dom("[data-new-topic-field-topic-header]").doesNotExist();

    this.set("topic", hiddenTopic);
    await settled();
    assert.dom("[data-new-topic-field-topic-header]").doesNotExist();
    assert.false(
      TaskGuidTopicHeader.shouldRender({ model: hiddenTopic }),
      "does not render without view permission"
    );

    this.set("topic", topicA);
    await settled();
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-a");
    assert.dom(".new-topic-field-topic-header__editor").doesNotExist();

    await click(".new-topic-field-status-badge__action");
    await fillIn("[data-new-topic-field-topic-guid]", "another-draft");
    this.set("topic", emptyTopic);
    await settled();
    this.set("topic", topicA);
    await settled();

    assert.dom(".new-topic-field-topic-header__editor").doesNotExist();
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-a");
  });

  test("applies a delayed update only to the originating topic", async function (assert) {
    const topicA = buildTopic({ id: 1, guid: "guid-a" });
    const topicB = buildTopic({ id: 2, guid: "guid-b" });
    const request = deferredResponse();
    let requestUrl;
    let requestOptions;

    window.fetch = (url, options) => {
      requestUrl = url;
      requestOptions = options;
      return request.promise;
    };
    this.set("topic", topicA);

    await render(
      <template><TopicAbovePostsFixture @topic={{this.topic}} /></template>
    );

    await click(".new-topic-field-status-badge__action");
    await fillIn("[data-new-topic-field-topic-guid]", "guid-a-updated");
    document.querySelector(".btn-primary").click();

    assert.strictEqual(
      requestUrl,
      "/new-topic-field/topics/1/guid.json",
      "sends the update for the originating topic"
    );
    assert.strictEqual(requestOptions.method, "PUT");
    assert.deepEqual(JSON.parse(requestOptions.body), {
      guid: "guid-a-updated",
    });

    this.set("topic", topicB);
    await settled();
    request.resolve({ guid: "guid-a-updated" });
    await waitUntil(() => topicA.task_guid === "guid-a-updated");
    await settled();

    assert.strictEqual(topicA.task_guid, "guid-a-updated");
    assert.strictEqual(topicB.task_guid, "guid-b");
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-b");
    assert.dom(".new-topic-field-topic-header__editor").doesNotExist();
  });

  test("applies a delayed delete only to the originating topic", async function (assert) {
    const topicA = buildTopic({ id: 1, guid: "guid-a" });
    const topicB = buildTopic({ id: 2, guid: "guid-b" });
    const request = deferredResponse();
    let requestUrl;
    let requestOptions;

    window.fetch = (url, options) => {
      requestUrl = url;
      requestOptions = options;
      return request.promise;
    };
    window.confirm = () => true;
    this.set("topic", topicA);

    await render(
      <template><TopicAbovePostsFixture @topic={{this.topic}} /></template>
    );

    await click(".new-topic-field-status-badge__action");
    document.querySelector(".btn-danger").click();

    assert.strictEqual(
      requestUrl,
      "/new-topic-field/topics/1/guid.json",
      "sends the delete for the originating topic"
    );
    assert.strictEqual(requestOptions.method, "DELETE");

    this.set("topic", topicB);
    await settled();
    request.resolve();
    await waitUntil(() => topicA.task_guid === null);
    await settled();

    assert.strictEqual(topicA.task_guid, null);
    assert.strictEqual(topicB.task_guid, "guid-b");
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-b");
    assert.dom(".new-topic-field-topic-header__editor").doesNotExist();
  });

  test("updates the visible GUID immediately after save and delete", async function (assert) {
    const topic = buildTopic({ id: 1, guid: "guid-before" });

    window.fetch = async (_url, options) => ({
      ok: true,
      status: 200,
      json: async () =>
        options.method === "PUT" ? { guid: "guid-after" } : {},
    });
    window.confirm = () => true;
    this.set("topic", topic);

    await render(
      <template><TopicAbovePostsFixture @topic={{this.topic}} /></template>
    );

    await click(".new-topic-field-status-badge__action");
    await fillIn("[data-new-topic-field-topic-guid]", "guid-after");
    await click(".btn-primary");

    assert.strictEqual(topic.task_guid, "guid-after");
    assert.dom(".new-topic-field-status-badge__guid").hasText("guid-after");
    assert.dom(".new-topic-field-topic-header__editor").doesNotExist();

    await click(".new-topic-field-status-badge__action");
    await click(".btn-danger");

    assert.strictEqual(topic.task_guid, null);
    assert.dom(".new-topic-field-status-badge__guid").doesNotExist();
    assert.dom("[data-new-topic-field-add-guid]").exists();
  });

  test("shows a link to the topic that already owns the GUID", async function (assert) {
    const topic = buildTopic({ id: 1, guid: "guid-before" });
    let dialogOptions;

    window.fetch = async () => ({
      ok: false,
      status: 409,
      json: async () => ({
        topic: {
          url: "https://forum.example.com/t/linked-topic/42",
        },
      }),
    });
    this.dialog.dialog = (options) => {
      dialogOptions = options;
    };
    this.set("topic", topic);

    await render(
      <template><TopicAbovePostsFixture @topic={{this.topic}} /></template>
    );

    await click(".new-topic-field-status-badge__action");
    await fillIn("[data-new-topic-field-topic-guid]", "duplicate-guid");
    await click(".btn-primary");

    const message = dialogOptions.message.toString();

    assert.strictEqual(dialogOptions.type, "alert");
    assert.true(
      message.includes(
        'href="https://forum.example.com/t/linked-topic/42"'
      )
    );
    assert.true(message.includes('target="_blank"'));
    assert.dom(".new-topic-field-topic-header__editor").exists();
  });
});
