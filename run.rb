#!/bin/env ruby
require 'rest_client'
require 'json'

CLIENT_ID = "d918cfcde64c388f44cbe0b85d506cd0cdd6f9adea74553795dcb1ecf8daf397"
CLIENT_SECRET = "e91b859350ca8a33226a0eff89a91292ed1041ff6e9cadd0c7c3a732879343f8"

REQUSET_HEADER = { 
    :content_type => 'application/json', 
    :trakt_api_version => '2',
    :trakt_api_key => CLIENT_ID
}
BASE_HOST = "https://api.trakt.tv"

def add_auth_to_header(token)
    REQUSET_HEADER.merge(:authorization => "Bearer #{token["access_token"]}")
end

def save_token(data)
    File.open("token.json", "w") { |w| w.write(data) }
end

def read_token
    if File.exists?("token.json")
        JSON.parse(File.read("token.json"))
    else
        return false
    end
end

def refresh_token(token)
    values = { 
        "refresh_token": token["refresh_token"], "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET,
        "redirect_uri": "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token"
    }
    response = RestClient.post BASE_HOST + '/oauth/token', values.to_json, REQUSET_HEADER
    save_token(response.body)
end

def new_authorize
    response = RestClient.post BASE_HOST + '/oauth/device/code', { "client_id": CLIENT_ID }.to_json , REQUSET_HEADER
    verification_url, interval, device_code, user_code, expire_in = JSON.parse(response).values_at("verification_url","interval","device_code","user_code", "expires_in")
    expire_at = Time.now + expire_in.to_i
    puts "Please go to #{verification_url} and enter this code #{user_code} to authorize app. Waiting for authorize.."
    while true

        if Time.now > expire_at
            puts "\nAuthorization expired"
            return false 
        end

        sleep interval.to_i
        RestClient.post(BASE_HOST + '/oauth/device/token', 
            {   "code": device_code,
                "client_id": CLIENT_ID, 
                "client_secret": CLIENT_SECRET 
            }.to_json , REQUSET_HEADER) { |response, request, result, &block|
                case response.code
                when 200
                    puts "\nAuthorized!"
                    save_token(response.body)
                    return true
                when 400
                    print "."                
                else
                    print "\n#{response.code}"
                    return false
                end
        }
    end
    return False
end

if read_token == false
    new_authorize
    puts "Run command again."
    exit
end

token = read_token

begin 
    response = RestClient.get BASE_HOST + '/users/settings', add_auth_to_header(token)
rescue RestClient::Unauthorized
    puts "Refreshing token.."
    refresh_token(token)
    puts "Run command again."
    exit
end

user_info = JSON.parse(response)

while true
    puts "Truncate movies or shows? [movies/shows]"
    history_type = gets.chomp
    break if ["movies","shows"].include?(history_type)
end

## History

response = RestClient.get(BASE_HOST + '/sync/watched/' + history_type, add_auth_to_header(token))
sync_data = JSON.parse(response)
puts "Found #{sync_data.count} in #{history_type} history"

trakt_ids = sync_data.collect { |i| i[history_type.delete_suffix('s')]["ids"]["trakt"] }
values = { "#{history_type}": [] }
trakt_ids.each { |trakt_id| values["#{history_type}".to_sym] << { "ids": { "trakt": trakt_id } } }

response = RestClient::Request.execute(:method => :post, :url => BASE_HOST + '/sync/history/remove', :payload => values.to_json, :headers => add_auth_to_header(token), :timeout => 1200)
deleted = JSON.parse(response)
puts "Result of removing from history: #{deleted["deleted"]}"

## Collection

response = RestClient.get(BASE_HOST + '/sync/collection/' + history_type, add_auth_to_header(token))
sync_data = JSON.parse(response)
puts "Found #{sync_data.count} in #{history_type} collection"

trakt_ids = sync_data.collect { |i| i[history_type.delete_suffix('s')]["ids"]["trakt"] }
values = { "#{history_type}": [] }
trakt_ids.each { |trakt_id| values["#{history_type}".to_sym] << { "ids": { "trakt": trakt_id } } }

response = RestClient::Request.execute(:method => :post, :url => BASE_HOST + '/sync/collection/remove', :payload => values.to_json, :headers => add_auth_to_header(token), :timeout => 1200)
deleted = JSON.parse(response)
puts "Result of removing from collection: #{deleted["deleted"]}"


