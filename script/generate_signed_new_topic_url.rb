# frozen_string_literal: true

require "openssl"
require "securerandom"
require "uri"

secret = ARGV[0]
guid = ARGV[1]
base_url = ARGV[2] || "https://forum.apogey.ru"
category = ARGV[3] || "Discussion"
tags = ARGV[4] || "Tech"
expires = (Time.now.to_i + 7200).to_s
nonce = SecureRandom.uuid

abort "Usage: ruby script/generate_signed_new_topic_url.rb SECRET GUID [BASE_URL] [CATEGORY] [TAGS]" if secret.to_s.empty? || guid.to_s.empty?

payload = [
  "v1",
  "guid=#{guid}",
  "expires=#{expires}",
  "nonce=#{nonce}",
].join("\n")

sig = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
params = {
  "category" => category,
  "tags" => tags,
  "guid" => guid,
  "expires" => expires,
  "nonce" => nonce,
  "sig" => sig,
}

puts "#{base_url}/new-topic?#{URI.encode_www_form(params)}"
