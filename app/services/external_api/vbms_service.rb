require "vbms"

class RailsVBMSLogger
  def log(event, data)
    case event
    when :request
      if data[:response_code] != 200
        name = data[:request].class.name.split("::").last

        Rails.logger.error(
          "VBMS HTTP Error #{data[:response_code]}\n" \
          "VBMS #{name} Response #{data[:response_body]}"
        )
      end
    end
  end
end

class ExternalApi::VBMSService
  def self.fetch_documents_for(download)
    @vbms_client ||= init_client

    request = VBMS::Requests::ListDocuments.new(download.file_number)

    documents = send_and_log_request(download.file_number, request)
    Rails.logger.info("VBMS Document list length: #{documents.length}")
    documents
  end

  def self.v2_fetch_documents_for(source)
    @vbms_client ||= init_client

    request = VBMS::Requests::FindDocumentVersionReference.new(source.file_number)
    documents = send_and_log_request(source.file_number, request)
    Rails.logger.info("VBMS Document list length: #{documents.length}")
    documents
  end

  def self.fetch_document_file(document)
    @vbms_client ||= init_client

    request = VBMS::Requests::FetchDocumentById.new(document.document_id)
    result = send_and_log_request(document.document_id, request)
    result&.content
  end

  def self.v2_fetch_document_file(document)
    @vbms_client ||= init_client

    request = VBMS::Requests::GetDocumentContent.new(document.document_id)
    result = send_and_log_request(document.document_id, request)
    result&.content
  end

  def self.init_client
    VBMS::Client.from_env_vars(logger: RailsVBMSLogger.new,
                               env_name: ENV["CONNECT_VBMS_ENV"],
                               use_forward_proxy: FeatureToggle.enabled?(:vbms_forward_proxy))
  end

  def self.send_and_log_request(id, request)
    name = request.class.name.split("::").last
    MetricsService.record("#{request.class} for #{id}",
                          service: :vbms,
                          name: name) do
      @vbms_client.send_request(request)
    end
  rescue VBMS::ClientError => e
    Rails.logger.error "#{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end
end
