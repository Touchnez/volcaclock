#include "LinkBridge.h"

#include <ableton/Link.hpp>
#include <mach/mach_time.h>
#include <chrono>
#include <memory>
#include <optional>

namespace
{
std::unique_ptr<ableton::Link> gLink;
std::optional<ableton::Link::SessionState> gState;
}

extern "C" {

void lb_create(double bpm)
{
  if (!gLink)
  {
    gLink = std::make_unique<ableton::Link>(bpm);
  }
}

void lb_enable(int on)
{
  if (gLink)
  {
    gLink->enable(on != 0);
  }
}

size_t lb_num_peers(void)
{
  return gLink ? gLink->numPeers() : 0;
}

void lb_capture(void)
{
  if (gLink)
  {
    gState.emplace(gLink->captureAppSessionState());
  }
}

double lb_tempo(void)
{
  return gState ? gState->tempo() : 0.0;
}

double lb_beat_at(int64_t micros, double quantum)
{
  return gState ? gState->beatAtTime(std::chrono::microseconds(micros), quantum) : 0.0;
}

int64_t lb_time_at_beat(double beat, double quantum)
{
  return gState ? gState->timeAtBeat(beat, quantum).count() : 0;
}

void lb_sample(int64_t *micros, uint64_t *host)
{
  const uint64_t h1 = mach_absolute_time();
  const int64_t m = gLink ? gLink->clock().micros().count() : 0;
  const uint64_t h2 = mach_absolute_time();
  *micros = m;
  *host = h1 + (h2 - h1) / 2;
}

}
