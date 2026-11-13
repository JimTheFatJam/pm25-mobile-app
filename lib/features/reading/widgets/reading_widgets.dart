import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/prediction_reading.dart';
import '../reading_state.dart' show DeviceLocation;

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// A low-profile card with a small tinted icon square and a title. Every
/// section uses this so spacing, radii and typography stay consistent; all
/// colours come from the theme (AppColors / ColorScheme).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.icon, required this.title, required this.child, this.trailing});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(kCardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconSquare(icon: icon),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: kGap),
            child,
          ],
        ),
      ),
    );
  }
}

/// Outlined icon on a faint blue square -- the app's one recurring motif.
class IconSquare extends StatelessWidget {
  const IconSquare({super.key, required this.icon, this.size = 32, this.color, this.background});
  final IconData icon;
  final double size;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? theme.app.iconTint, borderRadius: BorderRadius.circular(kInsetRadius)),
      child: Icon(icon, size: size * 0.56, color: color ?? theme.colorScheme.primary),
    );
  }
}

/// Small muted caption text.
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.italic = false});
  final String text;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text,
        style: theme.textTheme.bodySmall?.copyWith(fontStyle: italic ? FontStyle.italic : FontStyle.normal));
  }
}

/// Uppercase, letter-spaced eyebrow label.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: color));
  }
}

// ---------------------------------------------------------------------------
// Current location -- a light header row, not a card, so the hero below
// is the first heavy element on the screen.
// ---------------------------------------------------------------------------

/// Shows the locality (when a resolver provided one) and the device's own
/// GPS coordinates -- exactly the values sent to the backend. Grid cell
/// ids, centroids and other internals are never shown; before a fix exists,
/// [status] describes what is happening instead.
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, required this.icon, this.location, this.status});
  final IconData icon;
  final DeviceLocation? location;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = location;
    final place = loc?.placeName;
    final hasPlace = place != null && place.isNotEmpty;
    final primaryStyle = theme.textTheme.titleMedium;
    final secondaryStyle = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Current location'),
                const SizedBox(height: 3),
                if (loc == null)
                  Text(status ?? '', key: const Key('location-line'), style: primaryStyle)
                else ...[
                  if (hasPlace) ...[
                    Text(place, key: const Key('location-place'), style: primaryStyle),
                    const SizedBox(height: 2),
                  ],
                  // Device GPS coordinates (never the grid-cell centroid).
                  Text(loc.coordinatesLabel, key: const Key('location-coords'), style: hasPlace ? secondaryStyle : primaryStyle),
                  if (status != null) ...[const SizedBox(height: 2), Caption(status!)],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero: the reading. A white card with a category-coloured edge stripe,
// the eyebrow + category chip on one line, the large value, and the
// "as of" footer. The category colour tints only the stripe, chip and
// number -- never the whole card.
// ---------------------------------------------------------------------------

class ReadingHeadline extends StatelessWidget {
  const ReadingHeadline({super.key, required this.reading});
  final PredictionReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cls = reading.classification;
    final palette = categoryPalette(cls == null ? theme.colorScheme.primary : colorFromHex(cls.colorHex), theme);
    return Card(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: palette.raw),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full width so the chip sits at the right edge; on a
                    // narrow screen the Wrap drops it to a second line.
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          const Eyebrow('Estimated PM2.5'),
                          if (cls != null) CategoryBadge(label: cls.category, palette: palette),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // FittedBox keeps the number on one line at any text scale /
                    // width instead of overflowing.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(reading.pm25!.toStringAsFixed(1),
                              key: const Key('pm25-value'),
                              style: theme.textTheme.displayLarge?.copyWith(
                                  fontSize: 72, fontWeight: FontWeight.w800, height: 1.0, color: palette.accent, letterSpacing: -2.5)),
                          const SizedBox(width: 8),
                          Text(reading.units,
                              style: theme.textTheme.titleLarge?.copyWith(color: theme.app.muted, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        Icon(Icons.schedule_outlined, size: 14, color: theme.app.muted),
                        Text('as of', style: theme.textTheme.bodySmall),
                        Text(reading.asOfLocalLabel,
                            key: const Key('as-of-label'),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    if (cls != null) ...[
                      const SizedBox(height: 4),
                      Text(cls.schemeName, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category chip: faint category tint, thin outline, colour dot and the
/// label in capitals with contrast-corrected text.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.label, required this.palette});
  final String label;
  final CategoryPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(kInsetRadius),
        border: Border.all(color: palette.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: palette.raw, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(label.toUpperCase(),
                key: const Key('category-label'),
                style: theme.textTheme.labelSmall?.copyWith(color: palette.accent, fontSize: 13, letterSpacing: 1.0)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interpretation and protective guidance -- two compact cards.
// ---------------------------------------------------------------------------

class MeaningCard extends StatelessWidget {
  const MeaningCard({super.key, required this.reading});
  final PredictionReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cls = reading.classification;
    if (cls == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          icon: Icons.info_outline_rounded,
          title: 'What this means',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cls.interpretation, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 10),
              Caption(cls.basisNote, italic: true),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        SectionCard(
          icon: Icons.health_and_safety_outlined,
          title: 'Recommended guidance',
          child: Text(cls.guidance, key: const Key('guidance-text'), style: theme.textTheme.bodyLarge),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Why this prediction? -- a small diverging bar chart: one row per factor,
// bars grow left (pushed lower) or right (pushed higher) from a shared
// axis, scaled to the strongest displayed factor.
// ---------------------------------------------------------------------------

class WhyCard extends StatelessWidget {
  const WhyCard({super.key, required this.reading});
  final PredictionReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.app;
    if (!reading.explanationAvailable || reading.topFactors.isEmpty) {
      return SectionCard(
        icon: Icons.psychology_outlined,
        title: 'Why this prediction?',
        child: Text('An explanation is not available for this estimate.', style: theme.textTheme.bodyMedium),
      );
    }
    final maxMagnitude = reading.topFactors.fold<double>(0, (m, f) => f.magnitude > m ? f.magnitude : m);
    return SectionCard(
      icon: Icons.psychology_outlined,
      title: 'Why this prediction?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Caption('The ${reading.topFactors.length} model inputs that moved this estimate the most.'),
          const SizedBox(height: 12),
          // Legend / axis header
          Row(
            children: [
              Expanded(child: _LegendChip(text: 'Pushed lower', color: colors.lower, alignEnd: false)),
              const SizedBox(width: 12),
              Expanded(child: _LegendChip(text: 'Pushed higher', color: colors.higher, alignEnd: true)),
            ],
          ),
          const SizedBox(height: 8),
          for (final f in reading.topFactors) ...[
            _FactorRow(factor: f, fraction: maxMagnitude > 0 ? (f.magnitude / maxMagnitude).clamp(0.0, 1.0) : null),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: colors.subtleSurface, borderRadius: BorderRadius.circular(kInsetRadius)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: colors.muted),
                const SizedBox(width: 8),
                Expanded(child: Caption(reading.explanationNote, italic: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.text, required this.color, required this.alignEnd});
  final String text;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dot = Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    final label = Flexible(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: color)));
    return Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd ? [label, const SizedBox(width: 6), dot] : [dot, const SizedBox(width: 6), label],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor, required this.fraction});
  final ExplanationFactor factor;

  /// Relative |SHAP| against the strongest displayed factor (null = no
  /// magnitude available -> a fixed-length marker instead of a bar).
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.app;
    final higher = factor.pushedHigher;
    final accent = higher ? colors.higher : colors.lower;
    final directionText = higher ? 'Pushed the estimate higher' : 'Pushed the estimate lower';
    final widthFactor = (fraction ?? 0.35).clamp(0.06, 1.0);
    final bar = Container(
      height: 10,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.horizontal(left: Radius.circular(higher ? 0 : 5), right: Radius.circular(higher ? 5 : 0)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(factor.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(directionText,
            key: Key('direction-${factor.feature}'),
            style: theme.textTheme.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: higher ? const SizedBox.shrink() : FractionallySizedBox(widthFactor: widthFactor, child: bar),
              ),
            ),
            Container(width: 2, height: 16, color: colors.border),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: higher ? FractionallySizedBox(widthFactor: widthFactor, child: bar) : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// About this estimate (data freshness / non-live note, as-of, last updated)
// ---------------------------------------------------------------------------

class DataNoteCard extends StatelessWidget {
  const DataNoteCard({super.key, required this.reading, this.receivedAt, this.attribution});
  final PredictionReading reading;
  final DateTime? receivedAt;

  /// Small licence line for the place-name provider (null = none shown).
  final String? attribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = reading.stalenessDays;
    final lagLine = days == null
        ? null
        : (days <= 0
            ? 'The estimate is for a time within the last day.'
            : 'The estimate is for a time about $days day${days == 1 ? '' : 's'} behind real time.');
    final missing = reading.nMissingFeatures;
    final total = reading.nFeatures;
    final coverageLine = (missing != null && total != null && missing > 0)
        ? 'Some satellite inputs were unavailable for this time and place ($missing of $total model inputs missing, e.g. because of cloud cover); the model relied more on weather and neighbourhood data.'
        : null;
    return SectionCard(
      icon: Icons.satellite_alt_outlined,
      title: 'About this estimate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reading.dataNote, key: const Key('data-note'), style: theme.textTheme.bodyMedium),
          if (lagLine != null) ...[const SizedBox(height: 8), Caption(lagLine)],
          if (coverageLine != null) ...[const SizedBox(height: 6), Caption(coverageLine)],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          _MetaRow(icon: Icons.schedule_outlined, label: 'Estimate for', value: reading.asOfLocalLabel),
          if (receivedAt != null) ...[
            const SizedBox(height: 6),
            _MetaRow(icon: Icons.update_outlined, label: 'Last updated', value: _formatLocal(receivedAt!)),
          ],
          if (attribution != null) ...[
            const SizedBox(height: 10),
            Text(attribution!, key: const Key('place-attribution'), style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
          ],
        ],
      ),
    );
  }

  static String _formatLocal(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ampm = l.hour < 12 ? 'AM' : 'PM';
    return '${l.month}/${l.day}/${l.year}, $h:${l.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.app.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label: ', style: theme.textTheme.bodySmall),
            TextSpan(text: value, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
          ])),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status / loading / error card
// ---------------------------------------------------------------------------

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.progress = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(kCardPad + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (progress)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Padding(padding: const EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary)),
                  )
                else
                  IconSquare(icon: icon),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: kGap),
            Text(message, style: theme.textTheme.bodyMedium),
            if (actionLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (actionLabel != null) FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                if (secondaryLabel != null) OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
