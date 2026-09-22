.pragma library

// The shell can create a service twice when two plugin syncs race an async
// component load; it publishes the last one and orphans the first. Library
// state is shared across instances, so the newest instance claims ownership
// and the older ones go inert instead of ticking and writing alongside it.

var owner = null

function claim(instance) {
  if (owner && owner !== instance) {
    try { owner.superseded = true } catch (e) {}
  }
  owner = instance
}

function release(instance) {
  if (owner === instance) owner = null
}
