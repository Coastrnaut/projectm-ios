# Data Model: MOD-011 Modulation Mix Modes

- **Binding layer**: an `AudioFeatureBinding` in `AudioFeatureModulator`'s list. Layers of a parameter are
  its bindings in list order; at most `maximumBindingsPerTarget` (4) per parameter, 32 in all.
- **Running value**: Double, starts at the base, clamped to the registry range after each layer.
- **New error**: `AudioFeatureBindingError.tooManyLayers(ParameterID, limit: Int)`.
- **Scene**: unchanged shape; `$.bindings` may hold up to 4 entries per target; `expression` only on a
  target's first entry.
