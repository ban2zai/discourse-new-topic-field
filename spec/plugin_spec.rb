# frozen_string_literal: true

RSpec.describe "discourse-new-topic-field plugin" do
  fab!(:user)

  let(:guid) { "09abcfac-0e44-11f1-86e9-a94ec75f6b04" }

  before { SiteSetting.discourse_new_topic_field_enabled = true }

  it "stores task_guid from first post creation opts on the topic" do
    post =
      PostCreator.create!(
        user,
        title: "Topic with external task GUID",
        raw: "Body with enough characters for a valid Discourse post.",
        task_guid: guid,
      )

    expect(post.topic.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to eq(guid)
  end

  it "does not store task_guid on a second topic when guid is already linked" do
    first_post =
      PostCreator.create!(
        user,
        title: "First topic with external task GUID",
        raw: "Body with enough characters for a valid Discourse post.",
        task_guid: guid,
      )

    second_post =
      PostCreator.create!(
        user,
        title: "Second topic with the same external task GUID",
        raw: "Body with enough characters for another valid Discourse post.",
        task_guid: guid,
      )

    expect(first_post.topic.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to eq(guid)
    expect(second_post.topic.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to be_blank
  end
end
