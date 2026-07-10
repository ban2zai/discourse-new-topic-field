# frozen_string_literal: true

RSpec.describe DiscourseNewTopicField::TopicsController do
  fab!(:group)
  fab!(:allowed_user) { Fabricate(:user) }
  fab!(:regular_user) { Fabricate(:user) }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: regular_user) }
  fab!(:second_topic) { Fabricate(:topic) }

  let(:guid) { "09abcfac-0e44-11f1-86e9-a94ec75f6b04" }
  let(:lookup_token) { "lookup-token" }

  before do
    SiteSetting.discourse_new_topic_field_enabled = true
    group.add(allowed_user)
    SiteSetting.discourse_new_topic_field_allowed_groups = group.id.to_s
    SiteSetting.discourse_new_topic_field_lookup_token = lookup_token
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

  def empty_solution_response
    {
      "can_set_solution" => false,
      "has_solution" => false,
      "solution" => {
        "post_id" => nil,
        "marked_at" => nil,
        "marked_by" => {
          "id" => nil,
          "username" => nil,
        },
        "post_author" => {
          "id" => nil,
          "username" => nil,
        },
      },
    }
  end

  def expected_category_response
    {
      "category_name" => category.name,
      "category_id" => category.id,
      "category_slug" => category.slug,
    }
  end

  def stub_approval_payload
    stub_const(
      "TzApproval",
      Class.new do
        def self.topic_status_payload(topic)
          {
            ok: true,
            found: true,
            topic_id: topic.id,
            is_tz: true,
            ss_approved: false,
            ss_approved_by: {
              id: nil,
              username: nil,
              at: nil,
            },
            approvals: [
              {
                profile_prefix: "tz",
                is_applicable: false,
                approved: false,
                approved_by: {
                  id: nil,
                  username: nil,
                  at: nil,
                },
              },
              {
                profile_prefix: "ss",
                is_applicable: true,
                approved: true,
                approved_by: {
                  id: topic.user.id,
                  username: topic.user.username,
                  at: "2026-07-10T01:55:19Z",
                },
              },
              {
                profile_prefix: "../unsafe",
                is_applicable: true,
                approved: true,
                approved_by: {},
              },
            ],
            can_set_solution: true,
            has_solution: true,
            solution: {
              post_id: 999,
            },
          }
        end
      end,
    )
  end

  def expected_approval_response
    {
      "is_tz" => false,
      "tz_approved" => false,
      "tz_approved_by" => {
        "id" => nil,
        "username" => nil,
        "at" => nil,
      },
      "is_ss" => true,
      "ss_approved" => true,
      "ss_approved_by" => {
        "id" => topic.user.id,
        "username" => topic.user.username,
        "at" => "2026-07-10T01:55:19Z",
      },
    }
  end

  def stub_solved_topic(solved_topic)
    model = Class.new
    model.define_singleton_method(:find_by) { |topic_id:| solved_topic if topic_id.present? }

    solved_module = Module.new
    solved_module.const_set(:SolvedTopic, model)
    solved_module.const_set(:ENABLE_ACCEPTED_ANSWERS_CUSTOM_FIELD, "enable_accepted_answers")
    stub_const("DiscourseSolved", solved_module)
  end

  def enable_solutions
    category.custom_fields["enable_accepted_answers"] = "true"
    category.save_custom_fields(true)
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

  describe "GET /topic-guid-fields/topics/by-guid/:guid/:token" do
    it "returns the topic linked to the requested guid without sign in" do
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)

      body = response.parsed_body
      expect(body["ok"]).to eq(true)
      expect(body["found"]).to eq(true)
      expect(body["topic_id"]).to eq(topic.id)
      expect(body["guid"]).to eq(guid)
      expect(body["url"]).to eq(Discourse.base_url + topic.relative_url)
      expect(body["category"]).to eq(expected_category_response)
      expect(body).to include(empty_solution_response)
      expect(body["approval_status"]).to eq("available" => false, "data" => nil)
    end

    it "does not call guardian visibility checks" do
      store_guid(topic)
      Guardian.any_instance.expects(:can_see?).never

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
    end

    it "works when Discourse requires login globally" do
      SiteSetting.login_required = true
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include("ok" => true, "found" => true, "topic_id" => topic.id)
    end

    it "returns found false for an unknown guid" do
      unknown_guid = "unknown-guid"

      get "/topic-guid-fields/topics/by-guid/#{unknown_guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)

      body = response.parsed_body
      expect(body["ok"]).to eq(true)
      expect(body["found"]).to eq(false)
      expect(body["topic_id"]).to eq(nil)
      expect(body["guid"]).to eq(unknown_guid)
      expect(body["approval_status"]).to eq("available" => false, "data" => nil)
      expect(body).not_to have_key("category")
      expect(body).not_to have_key("can_set_solution")
      expect(body).not_to have_key("has_solution")
      expect(body).not_to have_key("solution")
    end

    it "returns found false for an invalid guid" do
      invalid_guid = "a" * (DiscourseNewTopicField::MAX_GUID_LENGTH + 1)

      get "/topic-guid-fields/topics/by-guid/#{invalid_guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include("ok" => true, "found" => false, "guid" => nil)
    end

    it "rejects an invalid token" do
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/wrong-token.json"

      expect(response.status).to eq(403)
      expect(response.parsed_body).to eq("ok" => false, "error" => "invalid_token")
    end

    it "rejects requests when the configured token is blank" do
      SiteSetting.discourse_new_topic_field_lookup_token = ""
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(403)
      expect(response.parsed_body).to eq("ok" => false, "error" => "invalid_token")
    end
  end

  describe "GET /topic-guid-fields/topics/by-topic/:topic_id/:token" do
    it "returns topic data and guid without sign in" do
      store_guid(topic)

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)

      body = response.parsed_body
      expect(body["ok"]).to eq(true)
      expect(body["found"]).to eq(true)
      expect(body["topic_id"]).to eq(topic.id)
      expect(body["guid"]).to eq(guid)
      expect(body["url"]).to eq(Discourse.base_url + topic.relative_url)
      expect(body["category"]).to eq(expected_category_response)
      expect(body).to include(empty_solution_response)
      expect(body["approval_status"]).to eq("available" => false, "data" => nil)
    end

    it "returns found true with null guid when the topic has no guid" do
      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)

      body = response.parsed_body
      expect(body["ok"]).to eq(true)
      expect(body["found"]).to eq(true)
      expect(body["topic_id"]).to eq(topic.id)
      expect(body["guid"]).to eq(nil)
    end

    it "falls back to TopicCustomField lookup when the custom field is not loaded on the topic" do
      store_guid(topic)
      Topic.any_instance.stubs(:custom_fields).returns({})

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["guid"]).to eq(guid)
    end

    it "works when Discourse requires login globally" do
      SiteSetting.login_required = true
      store_guid(topic)

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include("ok" => true, "found" => true, "topic_id" => topic.id)
    end

    it "returns found false for an unknown topic id" do
      unknown_topic_id = 999_999

      get "/topic-guid-fields/topics/by-topic/#{unknown_topic_id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "ok" => true,
        "found" => false,
        "topic_id" => unknown_topic_id,
        "guid" => nil,
        "approval_status" => {
          "available" => false,
          "data" => nil,
        },
      )
      expect(response.parsed_body).not_to have_key("category")
      expect(response.parsed_body).not_to have_key("can_set_solution")
      expect(response.parsed_body).not_to have_key("has_solution")
      expect(response.parsed_body).not_to have_key("solution")
    end

    it "returns null category fields when the topic has no category" do
      topic.update!(category: nil)

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["category"]).to eq(
        "category_name" => nil,
        "category_id" => nil,
        "category_slug" => nil,
      )
    end

    it "rejects an invalid token" do
      get "/topic-guid-fields/topics/by-topic/#{topic.id}/wrong-token.json"

      expect(response.status).to eq(403)
      expect(response.parsed_body).to eq("ok" => false, "error" => "invalid_token")
    end

    it "rejects requests when the configured token is blank" do
      SiteSetting.discourse_new_topic_field_lookup_token = ""

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(403)
      expect(response.parsed_body).to eq("ok" => false, "error" => "invalid_token")
    end
  end

  describe "optional approval integration" do
    it "returns unavailable approval status when TzApproval is absent" do
      hide_const("TzApproval")
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["approval_status"]).to eq("available" => false, "data" => nil)
    end

    it "keeps the approval wrapper stable when the integration fails" do
      stub_const(
        "TzApproval",
        Class.new do
          def self.topic_status_payload(_topic)
            raise "approval unavailable"
          end
        end,
      )
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["approval_status"]).to eq("available" => false, "data" => nil)
    end

    it "returns only dynamic profile fields for lookup by guid" do
      stub_approval_payload
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["approval_status"]).to eq(
        "available" => true,
        "data" => expected_approval_response,
      )
      expect(response.parsed_body).to include(empty_solution_response)
      expect(response.parsed_body.keys).to contain_exactly(
        "ok",
        "found",
        "topic_id",
        "guid",
        "title",
        "slug",
        "url",
        "created_at",
        "category",
        "can_set_solution",
        "has_solution",
        "solution",
        "approval_status",
      )
    end

    it "returns only dynamic profile fields for lookup by topic" do
      stub_approval_payload
      store_guid(topic)

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["approval_status"]).to eq(
        "available" => true,
        "data" => expected_approval_response,
      )
    end
  end

  describe "optional solved integration" do
    it "returns solution data independently from approval availability" do
      enable_solutions
      hide_const("TzApproval")
      answer_post = Fabricate(:post, topic: topic, user: regular_user, post_number: 2)
      marked_at = Time.zone.parse("2026-07-10 02:00:00 UTC")
      solved_topic =
        Struct
          .new(:answer_post_id, :accepter_user_id, :created_at, keyword_init: true)
          .new(
            answer_post_id: answer_post.id,
            accepter_user_id: allowed_user.id,
            created_at: marked_at,
          )
      stub_solved_topic(solved_topic)
      store_guid(topic)

      get "/topic-guid-fields/topics/by-guid/#{guid}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "can_set_solution" => true,
        "has_solution" => true,
        "solution" => {
          "post_id" => answer_post.id,
          "marked_at" => marked_at.iso8601(3),
          "marked_by" => {
            "id" => allowed_user.id,
            "username" => allowed_user.username,
          },
          "post_author" => {
            "id" => regular_user.id,
            "username" => regular_user.username,
          },
        },
        "approval_status" => {
          "available" => false,
          "data" => nil,
        },
      )
    end

    it "allows setting a solution when the category is enabled and the topic has a reply" do
      enable_solutions
      Fabricate(:post, topic: topic, user: regular_user, post_number: 2)
      stub_solved_topic(nil)

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        empty_solution_response.merge("can_set_solution" => true),
      )
    end

    it "returns the empty solution structure when DiscourseSolved is absent" do
      hide_const("DiscourseSolved")

      get "/topic-guid-fields/topics/by-topic/#{topic.id}/#{lookup_token}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(empty_solution_response)
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
