
class PushController < ApplicationController
	require 'net/http'
	require "open-uri"
	require 'openssl'
	require 'base64'
	require "digest"
	include OpenSSL

	def new

	end

	def index
	end

	def push_data
		before_key = params[:key] #1_key ブラウザ公開鍵を取得
		before_auth = params[:auth] #1_auth　authを取得
		endpoint = params[:endpoint] # endpointを取得
		$endpoint = endpoint.match(/https:\/\/android.googleapis.com\/gcm\/send\/([^\.]*)/)[1] #endpointからregistration_idを取得

		key = Base64.urlsafe_decode64(before_key) #1_key ブラウザ公開鍵をBase64デコーディング
		auth = Base64.urlsafe_decode64(before_auth) #1_auth authを取得してBase64デコーディング

		b_bn = OpenSSL::BN.new(key, 2) #1_key ブラウザ公開鍵データをOpenSSL::BNに格納
		b_group = OpenSSL::PKey::EC::Group.new("prime256v1")
		b = OpenSSL::PKey::EC::Point.new(b_group, b_bn) #1_key ブラウザ公開鍵データをOpenSSL::BNに格納
		b_binary = b.to_bn.to_s(2) # ブラウザ公開鍵データのバイナリ表現　(=key)

		s = OpenSSL::PKey::EC.new("prime256v1") #2 サーバー鍵
		s.generate_key #2 サーバー鍵ペアの生成
		pub_s = s.public_key.to_bn.to_s(2) #2 サーバー秘密鍵のバイナリーデータ

		ikm = s.dh_compute_key(b) #3 サーバー秘密鍵とブラウザ公開鍵から共有鍵を作成　バイナリデータ？

	  salt = OpenSSL::BN.rand(128) #4 salt生成
	  salt_binary = salt.to_bn.to_s(2) #4 saltのバイナリデータ
	  _PRK = OpenSSL::HMAC.digest("sha256", auth, ikm) #6
	  _IKM = OpenSSL::HMAC.digest("sha256", _PRK, "Content-Encoding: auth\x00\x01").byteslice(0, 32) #7
	  prk = OpenSSL::HMAC.digest("sha256", salt_binary, _IKM)
	  context = "P-256\x00\x00\x41#{b_binary}\x00\x41#{pub_s}" #¥¥¥¥¥¥
	  secret_key = OpenSSL::HMAC.digest("sha256", prk, "Content-Encoding: aesgcm\x00#{context}\x01").byteslice(0, 16)
	  nonce = OpenSSL::HMAC.digest("sha256", prk, "Content-Encoding: nonce\x00#{context}\x01").byteslice(0, 12)
	  $secret_key = secret_key
	  $nonce = nonce
	  $s = s
	  $salt = salt
	  $auth = auth
	end

	def create
		title = params[:content][:title]
		body = params[:content][:body]

		secret_key = $secret_key
		nonce = $nonce
		salt = $salt

		enc = OpenSSL::Cipher.new('aes-128-gcm')
		enc.encrypt

		data = {
			registration_ids: "#{$endpoint}",
			title: title,
			body: body
		}.to_json

		iv = $nonce
		enc.key = secret_key
		enc.iv = iv
		encrypted_data = ""
		encrypted_data << enc.update("\x00\x00#{data}")
		encrypted_data << enc.final
		encrypted_data << enc.auth_tag

    uri = URI.parse("https://gcm-http.googleapis.com/gcm/#{$endpoint}")
    logger.info "https://gcm-http.googleapis.com/gcm/#{$endpoint}"
    http = Net::HTTP.new(uri.host, uri.port)

    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri)

    request["Content-Length"] = encrypted_data.length.to_s
    request["Authorization"] = "key=(end_point)"
    request["Content-Type"] = "application/octet-stream"
    request["Crypto-Key"] = "keyid=p256dh;dh=#{Base64.urlsafe_encode64($s.public_key.to_bn.to_s(2))}"
    request["Encryption"] = "keyid=p256dh;salt=#{Base64.urlsafe_encode64(salt.to_bn.to_s(2))}"
    request["Content-Encoding"] = "aesgcm"
    request["TTL"] = "10"
		request.body = encrypted_data


		response = http.request(request)
		logger.info("output: #{response.body}")


		redirect_to "/"
	end

	def action1

	end

	def action2

	end
end

