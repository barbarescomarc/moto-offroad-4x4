import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'glass_control.dart';

// ── Segment d'un menu radial ─────────────────────────────────
class RadialMenuSegment {
  final IconData icon;
  final Color color;
  final VoidCallback onSelect;
  // Angle depuis la verticale basse, dans le sens horaire : 0 = bas,
  // 90 = droite, 180 = haut, 270 = gauche.
  final double angleDeg;

  const RadialMenuSegment({
    required this.icon,
    required this.color,
    required this.onSelect,
    required this.angleDeg,
  });
}

// ── Menu radial générique, boutons carrés arrondis ───────────
//
// Appui court sur le centre : action normale (ex. recentrer), inchangée.
// Appui long puis glissement sans relever le doigt : ouvre les segments,
// dont un se déclenche au relâcher — sans le temps de maintien
// supplémentaire du menu d'enregistrement, réservé à Arrêter : ici aucune
// action n'est destructrice, un relâchement accidentel n'a pas de
// conséquence grave.
class RadialActionMenu extends StatefulWidget {
  final IconData centerIcon;
  final Color centerColor;
  final bool centerActive;
  final VoidCallback onCenterTap;
  final List<RadialMenuSegment> segments;
  final double radius;

  const RadialActionMenu({
    super.key,
    required this.centerIcon,
    required this.centerColor,
    required this.onCenterTap,
    required this.segments,
    this.centerActive = false,
    this.radius = 82,
  });

  @override
  State<RadialActionMenu> createState() => _RadialActionMenuState();
}

class _RadialActionMenuState extends State<RadialActionMenu> {
  static const double _deadZoneRadius = 28;
  static const double _buttonSize = 40;

  bool _expanded = false;
  int _activeIndex = -1;

  Offset _segmentOffset(double angleDeg) {
    final rad = angleDeg * math.pi / 180;
    return Offset(widget.radius * math.sin(rad), widget.radius * math.cos(rad));
  }

  void _onLongPressStart(LongPressStartDetails d) {
    setState(() {
      _expanded = true;
      _activeIndex = -1;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    final offset = d.offsetFromOrigin;
    int nearest = -1;
    if (offset.distance >= _deadZoneRadius) {
      var best = double.infinity;
      for (var i = 0; i < widget.segments.length; i++) {
        final dist = (offset - _segmentOffset(widget.segments[i].angleDeg)).distance;
        if (dist < best) { best = dist; nearest = i; }
      }
    }
    if (nearest == _activeIndex) return;
    setState(() => _activeIndex = nearest);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final index = _activeIndex;
    setState(() {
      _expanded = false;
      _activeIndex = -1;
    });
    if (index >= 0) widget.segments[index].onSelect();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onCenterTap,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: SizedBox(
        width: _buttonSize,
        height: _buttonSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_expanded) ...[
              Positioned(
                top: _buttonSize / 2 - widget.radius,
                left: _buttonSize / 2 - widget.radius,
                child: Container(
                  width: widget.radius * 2,
                  height: widget.radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(.15), width: 1.5),
                  ),
                ),
              ),
              for (var i = 0; i < widget.segments.length; i++)
                Positioned(
                  top:  _segmentOffset(widget.segments[i].angleDeg).dy,
                  left: _segmentOffset(widget.segments[i].angleDeg).dx,
                  child: GlassPuck(
                    icon:   widget.segments[i].icon,
                    color:  widget.segments[i].color,
                    active: _activeIndex == i,
                    size:   _buttonSize,
                  ),
                ),
            ],
            GlassPuck(
              icon:   widget.centerIcon,
              color:  widget.centerColor,
              active: widget.centerActive,
              size:   _buttonSize,
            ),
          ],
        ),
      ),
    );
  }
}
