require "bgs"

# Thin interface to all things BGS
class ExternalApi::BGSService
  attr_reader :client

  def initialize(client: init_client)
    @client = client
  end

  def parse_veteran_info(veteran_data)
    ssn = veteran_data[:ssn] ? veteran_data[:ssn] : veteran_data[:soc_sec_number]
    last_four_ssn = ssn ? ssn[ssn.length - 4..ssn.length] : nil
    {
      "file_number" => veteran_data[:claim_number],
      "veteran_first_name" => veteran_data[:first_name],
      "veteran_last_name" => veteran_data[:last_name],
      "veteran_last_four_ssn" => last_four_ssn,
      "return_message" => veteran_data[:return_message]
    }
  end

  def fetch_veteran_info(file_number)
    veteran_data =
      MetricsService.record("BGS: fetch veteran info for vbms id: #{file_number}",
                            service: :bgs,
                            name: "veteran.find_by_file_number") do
        client.veteran.find_by_file_number(file_number)
      end
    parse_veteran_info(veteran_data) if veteran_data
  end

  def check_sensitivity(file_number)
    current_user = RequestStore[:current_user]

    MetricsService.record("BGS: can_access? (find_by_file_number): #{file_number}",
                          service: :bgs,
                          name: "can_access?") do
      client.can_access?(file_number, FeatureToggle.enabled?(:can_access_v2, user: current_user))
    end
  end

  def valid_file_number?(file_number)
    number = (file_number || "").strip
    return true if /^\d+$/ =~ number && number.length >= 8 && number.length <= 9
    false
  end

  def record_found?(veteran_info)
    return false unless veteran_info && veteran_info["return_message"]
    veteran_info["return_message"].include?("No BIRLS record found") ? false : true
  end

  def fetch_user_info(username)
    resp = client.common_security.get_css_user_stations(username)
    # example
    # {:network_login_name=>"CF_Q_283", :user_application=>"CASEFLOW", :user_stations=>{:enabled=>true, :id=>"283", :name=>"Hines SDC", :role=>"User"}}
    # TODO if we have more than one station
    css_id = resp[:network_login_name] # probably the same as username but just in case.
    station_id = Array.wrap(resp[:user_stations]).first[:id]

    resp2 = client.common_security.get_security_profile(username: css_id, station_id: station_id, application: "CASEFLOW")
    # example
    # {:appl_role=>"User", :bdn_num=>"1002", :email_address=>"caseflow@example.com",
    #  :file_num=>nil, :first_name=>"TEST", :functions=>[
    #     {:assigned_value=>"NO", :disable_ind=>"N", :name=>"Download eFolder"},
    #     {:assigned_value=>"NO", :disable_ind=>"N", :name=>"System Admin"}
    #  ],
    #  :job_title=>"Example Review Officer", :last_name=>"ONE", :message=>"Success", :middle_name=>nil, :participant_id=>"123"
    # }
    {
      css_id: css_id,
      station_id: station_id,
      first_name: resp2[:first_name],
      last_name: resp2[:last_name],
      email: resp2[:email_address],
      roles: Array.wrap(resp2[:functions]).select { |func| func[:assigned_value] == "YES" }.map { |func| func[:name] }
    }
  rescue BGS::ShareError
    {}
  end

  private

  def current_user
    RequestStore[:current_user]
  end

  def init_client
    forward_proxy_url = FeatureToggle.enabled?(:bgs_forward_proxy) ? ENV["RUBY_BGS_PROXY_BASE_URL"] : nil

    # We hardcode the ip since all clients show up as a single IP anyway.
    BGS::Services.new(
      env: Rails.application.config.bgs_environment,
      application: "CASEFLOW",
      client_ip: "10.236.66.133",
      client_station_id: current_user.station_id,
      client_username: current_user.css_id,
      ssl_cert_key_file: ENV["BGS_KEY_LOCATION"],
      ssl_cert_file: ENV["BGS_CERT_LOCATION"],
      ssl_ca_cert: ENV["BGS_CA_CERT_LOCATION"],
      forward_proxy_url: forward_proxy_url,
      jumpbox_url: ENV["RUBY_BGS_JUMPBOX_URL"],
      log: true
    )
  end
end
