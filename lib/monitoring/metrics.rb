module Monitoring
  module Metrics
    extend self

    def create_metric(metric, type) 
      case type.to_sym
      when :counter
        create_counter_metric(metric)
      when :gauge
        create_gauge_metric(metric)
      when :histogram
        create_histogram_metric(metric)
      else
        raise Exception.new "Invalid or missing metric type."
      end
    end

    private

    def create_gauge_metric(metric) 
      gauge = ::Prometheus::Client::Gauge.new(
        metric.metric_name,
        docstring: metric.docstring,
        labels: metric.labels,
        store_settings: {
          aggregation: :most_recent
        }
      )
      metric.registry.register(gauge)
      setup_subscriber(metric)
    end

    def create_counter_metric(metric) 
      counter = ::Prometheus::Client::Counter.new(
        metric.metric_name,
        docstring: metric.docstring,
        labels: metric.labels
      )
      metric.registry.register(counter)
      setup_subscriber(metric)
    end

    def create_histogram_metric(metric) 
      histogram = ::Prometheus::Client::Histogram.new(
        metric.metric_name,
        docstring: metric.docstring,
        labels: metric.labels
      )
      metric.registry.register(histogram)
      setup_subscriber(metric)
    end

    def setup_subscriber(metric)
      metric.pubsub.subscribe(metric.sub_event_name) do |payload|
        metric.update(payload)
      end
      throttle_policy_event(metric) unless !metric.throttle
    end

    def throttle_policy_event(metric)
      # TODO: revisit throttling for metrics which execute DB queries
      metric.pubsub.subscribe('conjur.policy_loaded') do
        metric.pubsub.publish(metric.sub_event_name)
      end
    end
  end
end
