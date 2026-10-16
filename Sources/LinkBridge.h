// Interface C minimale vers Ableton Link, appelable depuis Swift.
#ifndef LINK_BRIDGE_H
#define LINK_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void lb_create(double bpm);
void lb_enable(int on);
size_t lb_num_peers(void);

// Fige l'etat de la session Link ; les fonctions suivantes lisent cet etat fige.
void lb_capture(void);
double lb_tempo(void);
double lb_beat_at(int64_t micros, double quantum);
int64_t lb_time_at_beat(double beat, double quantum);

// Lit au meme instant l'horloge Link (microsecondes) et l'horloge machine (mach_absolute_time).
void lb_sample(int64_t *micros, uint64_t *host);

#ifdef __cplusplus
}
#endif

#endif
