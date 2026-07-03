# frozen_string_literal: true

# name: discourse-new-topic-field
# about: Stores an external task GUID on topics created from /new-topic links.
# version: 0.1.0
# authors: ban2zai
# required_version: 2.7.0

enabled_site_setting :discourse_new_topic_field_enabled

register_asset "stylesheets/common/new-topic-field.scss"

module ::DiscourseNewTopicField
  PLUGIN_NAME = "discourse-new-topic-field"
  FIELD_NAME = "discourse_new_topic_field_guid"
  CREATE_PARAM = :task_guid
  MAX_GUID_LENGTH = 128

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

  def self.topic_for_guid(guid, except_topic_id: nil)
    normalized_guid = normalize_guid(guid)
    return nil if normalized_guid.blank?

    fields = TopicCustomField.where(name: FIELD_NAME, value: normalized_guid)
    fields = fields.where.not(topic_id: except_topic_id) if except_topic_id.present?

    topic_id = fields.order(:topic_id).limit(1).pick(:topic_id)
    topic_id ? Topic.find_by(id: topic_id) : nil
  end

  def self.handle_post_created(post, opts)
    return unless SiteSetting.discourse_new_topic_field_enabled
    return unless post.post_number == 1

    store_topic_guid(post.topic, opts[CREATE_PARAM] || opts[CREATE_PARAM.to_s])
  rescue DuplicateGuidError
    false
  end
end

after_initialize do
  require_relative "app/controllers/discourse_new_topic_field/topics_controller"

  add_permitted_post_create_param(DiscourseNewTopicField::CREATE_PARAM)
  register_topic_custom_field_type(DiscourseNewTopicField::FIELD_NAME, :string)

  module ::DiscourseNewTopicField::GuardianExtensions
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
    if scope.can_manage_task_guid?(object.topic)
      object.topic.custom_fields[DiscourseNewTopicField::FIELD_NAME]
    end
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

    put "/new-topic-field/topics/:topic_id/guid" =>
          "discourse_new_topic_field/topics#update_guid",
        defaults: {
          format: :json,
        }
  end
end
