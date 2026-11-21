#ifndef RUNNER_MEMORY_METRICS_H_
#define RUNNER_MEMORY_METRICS_H_

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class MemoryMetrics {
 public:
  struct Options {
    uint32_t interval_ms = 5000;
    uint64_t minimum_allocation_bytes = 1024 * 1024;
    size_t max_allocations = 512;
    size_t max_changes = 512;
  };

  struct Counters {
    uint64_t committed_bytes = 0;
    uint64_t reserved_bytes = 0;
    uint64_t free_bytes = 0;
    uint64_t private_committed_bytes = 0;
    uint64_t private_reserved_bytes = 0;
    uint64_t mapped_committed_bytes = 0;
    uint64_t mapped_reserved_bytes = 0;
    uint64_t image_committed_bytes = 0;
    uint64_t image_reserved_bytes = 0;
    uint64_t other_committed_bytes = 0;
    uint64_t other_reserved_bytes = 0;
    uint64_t private_read_write_bytes = 0;
    uint64_t private_write_combine_bytes = 0;
    uint64_t private_other_bytes = 0;

    uint64_t allocated_bytes() const { return committed_bytes + reserved_bytes; }
    bool operator==(const Counters& other) const;
  };

  struct Allocation {
    uint64_t id = 0;
    Counters bytes;
    uint64_t region_count = 0;
    uint32_t type_flags = 0;
    uint32_t protection_flags = 0;
    bool above_threshold = false;
  };

  struct Change {
    std::string kind;
    uint64_t id = 0;
    Allocation before;
    Allocation after;
  };

  struct Snapshot {
    std::string status = "disabled";
    bool enabled = false;
    bool complete = false;
    uint64_t sample_id = 0;
    uint64_t tick_ms = 0;
    uint64_t scan_duration_us = 0;
    uint64_t scan_interval_ms = 0;
    uint32_t configured_interval_ms = 5000;
    uint32_t error_code = 0;
    uint64_t queried_region_count = 0;
    uint64_t allocation_count = 0;
    uint64_t eligible_allocation_count = 0;
    uint64_t eligible_allocation_bytes = 0;
    uint64_t eligible_committed_bytes = 0;
    uint64_t eligible_reserved_bytes = 0;
    uint64_t omitted_allocation_count = 0;
    uint64_t omitted_allocation_bytes = 0;
    uint64_t omitted_committed_bytes = 0;
    uint64_t omitted_reserved_bytes = 0;
    uint64_t created_count = 0;
    uint64_t changed_count = 0;
    uint64_t released_count = 0;
    uint64_t event_overflow = 0;
    bool truncated = false;
    Counters totals;
    std::vector<Allocation> allocations;
    std::vector<Change> changes;
  };

  MemoryMetrics();
  explicit MemoryMetrics(Options options);
  ~MemoryMetrics();
  MemoryMetrics(const MemoryMetrics&) = delete;
  MemoryMetrics& operator=(const MemoryMetrics&) = delete;

  void Start();
  void Stop();
  Snapshot ReadCachedSnapshot() const;

 private:
  struct Observed {
    uintptr_t base = 0;
    Allocation allocation;
  };
  struct Tracked {
    Allocation allocation;
  };

  void Run();
  Snapshot Scan(uint64_t previous_tick);
  void ApplyObservation(Snapshot& snapshot,
                        const std::map<uintptr_t, Allocation>& existing,
                        std::vector<Observed>& candidates);

  const Options options_;
  std::atomic<bool> stopping_{true};
  std::thread worker_;
  mutable std::mutex mutex_;
  std::condition_variable wake_;
  Snapshot latest_;
  std::map<uintptr_t, Tracked> tracked_;
  uint64_t next_id_ = 1;
  uint64_t sample_id_ = 0;
};

#endif
