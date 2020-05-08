class Api::V2::ApplicationController < Api::V1::ApplicationController
  private

  def bgs_service
    @bgs_service ||= BGSService.new
  end

  def veteran_not_found(file_number)
    render json: { status: "eFolder Express could not find an eFolder with the Veteran ID #{file_number}. Check to make sure you entered the ID correctly and try again." }, status: 400
  end

  def vso_denied_record
    forbidden("This efolder belongs to a Veteran you do not represent. Please contact your supervisor.")
  end

  def invalid_file_number
    render json: { status: "File number is invalid. Veteran IDs must be 8 or more characters and contain only numbers." }, status: 400
  end

  def verify_veteran_file_number
    file_number = request.headers["HTTP_FILE_NUMBER"]
    return missing_header("File Number") unless file_number

    return invalid_file_number unless bgs_service.valid_file_number?(file_number)

    fetch_veteran_by_file_number(file_number)
  end

  def fetch_veteran_by_file_number(file_number)
    if FeatureToggle.enabled?(:user_authorizer, user: current_user)
      fetch_veteran_with_user_authorizer(file_number)
    else
      fetch_veteran_with_bgs_service(file_number)
    end
  end

  def fetch_veteran_with_user_authorizer(file_number)
    authorizer = UserAuthorizer.new(user: current_user, file_number: file_number)
    if authorizer.can_read_efolder? && authorizer.veteran_record_found?
      authorizer.veteran_record["file_number"] || file_number
    elsif authorizer.sensitive_file?
      sensitive_record
    elsif authorizer.veteran_record_poa_denied?
      vso_denied_record
    elsif !authorizer.veteran_record_found?
      veteran_not_found(file_number)
    else
      raise BGS::ShareError, "Cannot access Veteran record"
    end
  end

  def fetch_veteran_with_bgs_service(file_number)
    begin
      veteran_info = bgs_service.fetch_veteran_info(file_number)
    rescue StandardError => e
      return sensitive_record if e.message.include?("Sensitive File - Access Violation")
      return vso_denied_record if e.message.include?("Power of Attorney of Folder is")
      raise e
    end

    return veteran_not_found(file_number) unless bgs_service.record_found?(veteran_info)

    veteran_info["file_number"] || file_number
  end
end
