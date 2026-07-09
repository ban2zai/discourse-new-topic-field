# frozen_string_literal: true

# name: discourse-new-topic-field
# about: Stores an external task GUID on topics created from /new-topic links.
# version: 0.1.0
# authors: ban2zai
# required_version: 2.7.0

require "digest"
require "openssl"

enabled_site_setting :discourse_new_topic_field_enabled

register_asset "stylesheets/common/new-topic-field.scss"

module ::DiscourseNewTopicField
  PLUGIN_NAME = "discourse-new-topic-field"
  FIELD_NAME = "discourse_new_topic_field_guid"
  CREATE_PARAM = :task_guid
  CREATE_SIGNATURE_EXPIRES_PARAM = :task_guid_expires
  CREATE_SIGNATURE_NONCE_PARAM = :task_guid_nonce
  CREATE_SIGNATURE_PARAM = :task_guid_sig
  MAX_GUID_LENGTH = 128
  MAX_SIGNATURE_PARAM_LENGTH = 128
  SIGNATURE_VERSION = "v1"
  SIGNATURE_ALGORITHM = "SHA256"
  SIGNATURE_HEX_REGEXP = /\A\h{64}\z/

  class DuplicateGuidError < StandardError
    attr_reader :topic

    def initialize(topic)
      @topic = topic
      super("Task GUID is already linked to topic ##{topic.id}")
    end
  end

  def self.allowed_group_ids
    SiteSetting.discourse_new_topic_field_allowed_groups_map
  end

  def self.normalize_guid(value)
    guid = value.to_s.strip
    return nil if guid.blank? || guid.length > MAX_GUID_LENGTH

    guid
  end

  def self.store_topic_guid(topic, guid)
    normalized_guid = normalize_guid(guid)
    return false if normalized_guid.blank?

    existing_topic = topic_for_guid(normalized_guid, except_topic_id: topic.id)
    raise DuplicateGuidError.new(existing_topic) if existing_topic

    topic.custom_fields[FIELD_NAME] = normalized_guid
    topic.save_custom_fields(true)
    true
  end

  def self.signature_payload(guid, expires, nonce)
    [
      SIGNATURE_VERSION,
      "guid=#{guid}",
      "expires=#{expires}",
      "nonce=#{nonce}",
    ].join("\n")
  end

  def self.signature_for(guid:, expires:, nonce:, secret: SiteSetting.discourse_new_topic_field_signature_secret)
    OpenSSL::HMAC.hexdigest(SIGNATURE_ALGORITHM, secret.to_s, signature_payload(guid, expires, nonce))
  end

  def self.valid_signature?(guid:, expires:, nonce:, sig:)
    return true unless SiteSetting.discourse_new_topic_field_require_signature

    secret = SiteSetting.discourse_new_topic_field_signature_secret.to_s
    normalized_guid = normalize_guid(guid)
    expires = expires.to_s.strip
    nonce = nonce.to_s.strip
    sig = sig.to_s.strip.downcase
    expires_i = Integer(expires, exception: false)

    return false if secret.blank?
    return false if normalized_guid.blank?
    return false if expires_i.blank? || expires_i < Time.zone.now.to_i
    return false if nonce.blank? || nonce.length > MAX_SIGNATURE_PARAM_LENGTH
    return false if sig.blank? || sig.length > MAX_SIGNATURE_PARAM_LENGTH || !SIGNATURE_HEX_REGEXP.match?(sig)

    expected_sig = signature_for(guid: normalized_guid, expires: expires, nonce: nonce, secret: secret)
    ActiveSupport::SecurityUtils.secure_compare(expected_sig, sig)
  end

  def self.valid_create_signature?(guid, opts)
    valid_signature?(
      guid: guid,
      expires: opts[CREATE_SIGNATURE_EXPIRES_PARAM] || opts[CREATE_SIGNATURE_EXPIRES_PARAM.to_s],
      nonce: opts[CREATE_SIGNATURE_NONCE_PARAM] || opts[CREATE_SIGNATURE_NONCE_PARAM.to_s],
      sig: opts[CREATE_SIGNATURE_PARAM] || opts[CREATE_SIGNATURE_PARAM.to_s],
    )
  end

  def self.clear_topic_guid(topic)
    topic.custom_fields[FIELD_NAME] = nil
    topic.save_custom_fields(true)
    TopicCustomField.where(topic_id: topic.id, name: FIELD_NAME).delete_all
    true
  end

  def self.topic_for_guid(guid, except_topic_id: nil)
    normalized_guid = normalize_guid(guid)
    return nil if normalized_guid.blank?

    fields = TopicCustomField.where(name: FIELD_NAME, value: normalized_guid)
    fields = fields.where.not(topic_id: except_topic_id) if except_topic_id.present?

    topic_id = fields.order(:topic_id).limit(1).pick(:topic_id)
    topic_id ? Topic.find_by(id: topic_id) : nil
  end

  def self.lookup_token_valid?(token)
    configured_token = SiteSetting.discourse_new_topic_field_lookup_token.to_s
    provided_token = token.to_s

    return false if configured_token.blank? || provided_token.blank?

    configured_digest = Digest::SHA256.hexdigest(configured_token)
    provided_digest = Digest::SHA256.hexdigest(provided_token)
    ActiveSupport::SecurityUtils.secure_compare(configured_digest, provided_digest)
  end

  def self.handle_post_created(post, opts)
    return unless SiteSetting.discourse_new_topic_field_enabled
    return unless post.post_number == 1

    guid = opts[CREATE_PARAM] || opts[CREATE_PARAM.to_s]
    return if normalize_guid(guid).blank?
    return false unless valid_create_signature?(guid, opts)

    store_topic_guid(post.topic, guid)
  rescue DuplicateGuidError
    false
  end
end

after_initialize do
  require_relative "app/controllers/discourse_new_topic_field/topics_controller"

  add_permitted_post_create_param(DiscourseNewTopicField::CREATE_PARAM)
  add_permitted_post_create_param(DiscourseNewTopicField::CREATE_SIGNATURE_EXPIRES_PARAM)
  add_permitted_post_create_param(DiscourseNewTopicField::CREATE_SIGNATURE_NONCE_PARAM)
  add_permitted_post_create_param(DiscourseNewTopicField::CREATE_SIGNATURE_PARAM)
  register_topic_custom_field_type(DiscourseNewTopicField::FIELD_NAME, :string)

  module ::DiscourseNewTopicField::GuardianExtensions
    def can_view_task_guid?(topic = nil)
      return false unless SiteSetting.discourse_new_topic_field_enabled
      return false if @user.blank?

      can_manage_task_guid?(topic) || (topic.present? && topic.user_id == @user.id)
    end

    def can_manage_task_guid?(_topic = nil)
      return false unless SiteSetting.discourse_new_topic_field_enabled

      allowed_group_ids = DiscourseNewTopicField.allowed_group_ids
      allowed_group_ids.present? && @user&.in_any_groups?(allowed_group_ids)
    end

    def ensure_can_manage_task_guid!(topic = nil)
      raise Discourse::InvalidAccess.new unless can_manage_task_guid?(topic)
    end
  end

  reloadable_patch { ::Guardian.prepend(::DiscourseNewTopicField::GuardianExtensions) }

  add_to_serializer(:topic_view, :task_guid) do
    if scope.can_view_task_guid?(object.topic)
      object.topic.custom_fields[DiscourseNewTopicField::FIELD_NAME]
    end
  end

  add_to_serializer(:topic_view, :can_view_task_guid) do
    scope.can_view_task_guid?(object.topic)
  end

  add_to_serializer(:topic_view, :can_manage_task_guid) do
    scope.can_manage_task_guid?(object.topic)
  end

  on(:post_created) { |post, opts| DiscourseNewTopicField.handle_post_created(post, opts) }

  Discourse::Application.routes.append do
    get "/new-topic-field/topics" => "discourse_new_topic_field/topics#index",
        defaults: {
          format: :json,
        }

    get "/new-topic-field/signature/validate" =>
          "discourse_new_topic_field/topics#validate_signature",
        defaults: {
          format: :json,
        }

    get "/topic-guid-fields/topics/by-guid/:guid/:token" =>
          "discourse_new_topic_field/topics#by_guid",
        defaults: {
          format: :json,
        }

    get "/topic-guid-fields/topics/by-topic/:topic_id/:token" =>
          "discourse_new_topic_field/topics#by_topic",
        defaults: {
          format: :json,
        }

    put "/new-topic-field/topics/:topic_id/guid" =>
          "discourse_new_topic_field/topics#update_guid",
        defaults: {
          format: :json,
        }

    delete "/new-topic-field/topics/:topic_id/guid" =>
             "discourse_new_topic_field/topics#destroy_guid",
           defaults: {
             format: :json,
           }
  end
end
