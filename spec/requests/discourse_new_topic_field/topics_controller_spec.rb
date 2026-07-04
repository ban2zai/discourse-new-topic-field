# frozen_string_literal: true

RSpec.describe DiscourseNewTopicField::TopicsController do
  fab!(:group)
  fab!(:allowed_user) { Fabricate(:user) }
  fab!(:regular_user) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: regular_user) }
  fab!(:second_topic) { Fabricate(:topic) }

  let(:guid) { "09abcfac-0e44-11f1-86e9-a94ec75f6b04" }

  before do
    SiteSetting.discourse_new_topic_field_enabled = true
    group.add(allowed_user)
    SiteSetting.discourse_new_topic_field_allowed_groups = group.id.to_s
  end

  def store_guid(topic, value = guid)
    topic.custom_fields[DiscourseNewTopicField::FIELD_NAME] = value
    topic.save_custom_fields(true)
  end

  def signature_params(guid, expires: 1.hour.from_now.to_i, nonce: "test-nonce")
    {
      guid: guid,
      expires: expires.to_s,
      nonce: nonce,
      sig:
        DiscourseNewTopicField.signature_for(
          guid: guid,
          expires: expires.to_s,
          nonce: nonce,
          secret: SiteSetting.discourse_new_topic_field_signature_secret,
        ),
    }
  end

  describe "GET /new-topic-field/topics" do
    it "returns the topic linked to the requested guid" do
      store_guid(topic)

      get "/new-topic-field/topics.json", params: { guid: guid }

      expect(response.status).to eq(200)
      expect(response.parsed_body["topics"].map { |item| item["topic_id"] }).to eq([topic.id])
    end

    it "requires a guid" do
      get "/new-topic-field/topics.json"

      expect(response.status).to eq(422)
    end
  end

  describe "GET /new-topic-field/signature/validate" do
    before do
      SiteSetting.discourse_new_topic_field_require_signature = true
      SiteSetting.discourse_new_topic_field_signature_secret = "test-secret"
    end

    it "accepts a valid signature" do
      get "/new-topic-field/signature/validate.json", params: signature_params(guid)

      expect(response.status).to eq(200)
    end

    it "rejects an invalid signature" do
      get "/new-topic-field/signature/validate.json",
          params: signature_params(guid).merge(sig: "0" * 64)

      expect(response.status).to eq(403)
    end

    it "rejects an expired signature" do
      get "/new-topic-field/signature/validate.json",
          params: signature_params(guid, expires: 1.minute.ago.to_i)

      expect(response.status).to eq(403)
    end
  end

  describe "PUT /new-topic-field/topics/:topic_id/guid" do
    it "allows configured group members to set guid" do
      sign_in(allowed_user)

      put "/new-topic-field/topics/#{topic.id}/guid.json", params: { guid: guid }

      expect(response.status).to eq(200)
      expect(topic.reload.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to eq(guid)
    end

    it "does not allow the same guid on another topic" do
      store_guid(topic)
      sign_in(allowed_user)

      put "/new-topic-field/topics/#{second_topic.id}/guid.json", params: { guid: guid }

      expect(response.status).to eq(409)
      expect(response.parsed_body["topic"]["topic_id"]).to eq(topic.id)
      expect(second_topic.reload.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to be_blank
    end

    it "blocks users outside configured groups" do
      sign_in(regular_user)

      put "/new-topic-field/topics/#{topic.id}/guid.json", params: { guid: guid }

      expect(response.status).to eq(403)
    end
  end

  describe "DELETE /new-topic-field/topics/:topic_id/guid" do
    it "allows configured group members to delete guid and frees it for another topic" do
      store_guid(topic)
      sign_in(allowed_user)

      delete "/new-topic-field/topics/#{topic.id}/guid.json"

      expect(response.status).to eq(200)
      expect(topic.reload.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to be_blank

      put "/new-topic-field/topics/#{second_topic.id}/guid.json", params: { guid: guid }

      expect(response.status).to eq(200)
      expect(second_topic.reload.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to eq(guid)
    end

    it "blocks topic authors outside configured groups from deleting guid" do
      store_guid(topic)
      sign_in(regular_user)

      delete "/new-topic-field/topics/#{topic.id}/guid.json"

      expect(response.status).to eq(403)
      expect(topic.reload.custom_fields[DiscourseNewTopicField::FIELD_NAME]).to eq(guid)
    end
  end
end
