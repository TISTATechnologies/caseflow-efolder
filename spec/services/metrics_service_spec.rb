describe MetricsService do
  context ".timer" do
    let(:labels) { { app: "eFolder", name: "ListDocuments" } }
    let(:yield_val) { 5 }
    subject do
      MetricsService.record("fake api call", service: "vbms", name: "ListDocuments") { yield_val }
    end

    it "returns yield value" do
      expect(subject).to eq(yield_val)
    end

    it "sends prometheus metrics" do
      counter = PrometheusService.vbms_request_attempt_counter
      current_counter = counter.values[labels] || 0

      subject

      gauge = PrometheusService.vbms_request_latency.gauge
      gauge_labels = gauge.values.keys.first
      expect(gauge_labels[:app]).to eq("eFolder")
      expect(gauge_labels[:name]).to eq("ListDocuments")

      expect(counter.values[labels]).to eq(current_counter + 1)

      # Ensure a value has been assigned
      expect(gauge.values[labels]).to be_truthy
    end

    it "increments error counter on error" do
      counter = PrometheusService.vbms_request_error_counter
      current_counter = counter.values[labels] || 0

      expect do
        MetricsService.record("fake api call", service: "vbms", name: "ListDocuments") { raise("hi") }
      end.to raise_error("hi")

      expect(counter.values[labels]).to eq(current_counter + 1)
    end
  end
end
