# frozen_string_literal: true

RSpec.describe "discourse-new-topic-field plugin" do
  fab!(:user)
  fab!(:group)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:other_user) { Fabricate(:user) }
  fab!(:manager) { Fabricate(:user) }

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

  it "allows topic authors to view task guid without managing it" do
    guardian = Guardian.new(user)

    expect(guardian.can_view_task_guid?(topic)).to eq(true)
    expect(guardian.can_manage_task_guid?(topic)).to eq(false)
  end

  it "allows configured group members to view and manage task guid" do
    group.add(manager)
    SiteSetting.discourse_new_topic_field_allowed_groups = group.id.to_s

    guardian = Guardian.new(manager)

    expect(guardian.can_view_task_guid?(topic)).to eq(true)
    expect(guardian.can_manage_task_guid?(topic)).to eq(true)
  end

  it "does not allow unrelated users to view task guid" do
    guardian = Guardian.new(other_user)

    expect(guardian.can_view_task_guid?(topic)).to eq(false)
    expect(guardian.can_manage_task_guid?(topic)).to eq(false)
  end
end
