import { module, test } from "qunit";
import duplicateGuidMessage from "discourse/plugins/discourse-new-topic-field/discourse/lib/duplicate-guid-message";

module("Unit | Lib | duplicate-guid-message", function () {
  test("adds a safe link when the duplicate topic is visible", function (assert) {
    const message = duplicateGuidMessage({
      url: "https://forum.example.com/t/linked-topic/42",
    }).toString();

    assert.true(
      message.includes(
        'href="https://forum.example.com/t/linked-topic/42"'
      )
    );
    assert.true(message.includes('target="_blank"'));
    assert.true(message.includes('rel="noopener noreferrer"'));
  });

  test("keeps the original message when topic details are unavailable", function (assert) {
    const message = duplicateGuidMessage();

    assert.strictEqual(typeof message, "string");
    assert.false(message.includes("<a "));
  });
});
