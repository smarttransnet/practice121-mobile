import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/models/prescription_item.dart';
import '../../data/services/favorites_service.dart';

/// Interactive Prescription Widget that supports:
///   1. Sentence View Mode (Default read-only presentation for end-users)
///   2. Directly Editable Grid Mode with ComboBox search, custom typing,
///      auto-fill from Favourites, and row management.
class PrescriptionGridWidget extends ConsumerStatefulWidget {
  const PrescriptionGridWidget({
    super.key,
    required this.initialRawPrescription,
    required this.onPrescriptionChanged,
  });

  final String initialRawPrescription;
  final void Function(List<PrescriptionItem> items, String rawJson, String sentenceText) onPrescriptionChanged;

  @override
  ConsumerState<PrescriptionGridWidget> createState() => _PrescriptionGridWidgetState();
}

class _PrescriptionGridWidgetState extends ConsumerState<PrescriptionGridWidget> {
  late List<PrescriptionItem> _items;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _parseInitial();
  }

  @override
  void didUpdateWidget(covariant PrescriptionGridWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRawPrescription != widget.initialRawPrescription && !_isEditing) {
      _parseInitial();
    }
  }

  void _parseInitial() {
    _items = PrescriptionItem.fromRaw(widget.initialRawPrescription);
    if (_items.isEmpty) {
      _items = [PrescriptionItem()];
    }
  }

  void _notifyChanges() {
    final validItems = _items.where((i) {
      return (i.genericName?.trim().isNotEmpty ?? false) ||
             (i.brandName?.trim().isNotEmpty ?? false) ||
             (i.dose?.trim().isNotEmpty ?? false) ||
             (i.frequency?.trim().isNotEmpty ?? false) ||
             (i.duration?.trim().isNotEmpty ?? false);
    }).toList();

    final rawJson = jsonEncode(validItems.map((e) => e.toJson()).toList());
    final sentenceText = validItems.map((e) => e.toSentenceString()).where((s) => s.isNotEmpty).join('\n');
    widget.onPrescriptionChanged(validItems, rawJson, sentenceText);
  }

  void _addRow() {
    setState(() {
      _items.add(PrescriptionItem());
    });
  }

  void _removeRow(int index) {
    setState(() {
      _items.removeAt(index);
      if (_items.isEmpty) {
        _items.add(PrescriptionItem());
      }
    });
  }

  void _handleFavoriteSelect(int index, FavoriteMedicineDto fav, {required bool isGeneric}) {
    setState(() {
      final item = _items[index];
      if (fav.genericName.isNotEmpty) item.genericName = fav.genericName;
      if (fav.brandName != null && fav.brandName!.isNotEmpty) item.brandName = fav.brandName;
      if (fav.dose != null && fav.dose!.isNotEmpty) item.dose = fav.dose;
      if (fav.frequency != null && fav.frequency!.isNotEmpty) item.frequency = fav.frequency;
      if (fav.duration != null && fav.duration!.isNotEmpty) item.duration = fav.duration;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favoritesAsync = ref.watch(favoriteMedicinesProvider);
    final favorites = favoritesAsync.asData?.value ?? FavoritesService.defaultFallbackFavorites;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode Header Action Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isEditing ? 'Edit Prescription Grid' : 'Prescription Summary',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    if (_isEditing) {
                      _notifyChanges();
                    }
                    _isEditing = !_isEditing;
                  });
                },
                icon: Icon(_isEditing ? Icons.check_circle_outline_rounded : Icons.edit_note_rounded, size: 18),
                label: Text(_isEditing ? 'Done Editing' : 'Edit Prescription'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Body: Sentence View vs Grid Edit View
        Expanded(
          child: _isEditing
              ? _buildGridEditView(context, theme, favorites)
              : _buildSentenceView(context, theme),
        ),
      ],
    );
  }

  Widget _buildSentenceView(BuildContext context, ThemeData theme) {
    final validItems = _items.where((i) => i.toSentenceString().isNotEmpty).toList();

    if (validItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.medical_information_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'No prescription items found.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Prescription'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: validItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = validItems[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.toSentenceString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGridEditView(BuildContext context, ThemeData theme, List<FavoriteMedicineDto> favorites) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.all(12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2), // Medicine (Generic & Brand)
                1: FlexColumnWidth(1.2), // Dose
                2: FlexColumnWidth(1.0), // Frequency
                3: FlexColumnWidth(1.0), // Duration
                4: FixedColumnWidth(40),  // Action
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                // Header Row
                TableRow(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  children: const [
                    Padding(padding: EdgeInsets.all(8), child: Text('Medicine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Padding(padding: EdgeInsets.all(8), child: Text('Dose', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Padding(padding: EdgeInsets.all(8), child: Text('Freq.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Padding(padding: EdgeInsets.all(8), child: Text('Dur.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    SizedBox(),
                  ],
                ),
                // Item Rows
                for (int i = 0; i < _items.length; i++)
                  _buildEditableRow(context, theme, favorites, i),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Row'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _notifyChanges();
                      _isEditing = false;
                    });
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save & View'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _buildEditableRow(
    BuildContext context,
    ThemeData theme,
    List<FavoriteMedicineDto> favorites,
    int index,
  ) {
    final item = _items[index];

    return TableRow(
      children: [
        // Medicine Column: Generic Name ComboBox + Brand Name ComboBox
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            children: [
              _buildComboBox(
                context: context,
                hintText: 'Generic Name',
                initialValue: item.genericName ?? '',
                options: favorites.map((f) => f.genericName).where((s) => s.isNotEmpty).toSet().toList(),
                onChanged: (val) => item.genericName = val,
                onSelected: (val) {
                  final fav = favorites.firstWhere((f) => f.genericName == val, orElse: () => FavoriteMedicineDto(id: '', genericName: val));
                  _handleFavoriteSelect(index, fav, isGeneric: true);
                },
              ),
              const SizedBox(height: 4),
              _buildComboBox(
                context: context,
                hintText: 'Brand Name',
                initialValue: item.brandName ?? '',
                options: favorites.map((f) => f.brandName).whereType<String>().where((s) => s.isNotEmpty).toSet().toList(),
                onChanged: (val) => item.brandName = val,
                onSelected: (val) {
                  final fav = favorites.firstWhere((f) => f.brandName == val, orElse: () => FavoriteMedicineDto(id: '', genericName: val, brandName: val));
                  _handleFavoriteSelect(index, fav, isGeneric: false);
                },
              ),
            ],
          ),
        ),
        // Dose Column
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: TextFormField(
            initialValue: item.dose ?? '',
            decoration: const InputDecoration(
              hintText: 'e.g. 500mg',
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (val) => item.dose = val,
          ),
        ),
        // Frequency Column
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: TextFormField(
            initialValue: item.frequency ?? '',
            decoration: const InputDecoration(
              hintText: 'e.g. BD',
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (val) => item.frequency = val,
          ),
        ),
        // Duration Column
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: TextFormField(
            initialValue: item.duration ?? '',
            decoration: const InputDecoration(
              hintText: 'e.g. 5 days',
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (val) => item.duration = val,
          ),
        ),
        // Remove Action Column
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red, size: 20),
            onPressed: () => _removeRow(index),
            tooltip: 'Remove row',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildComboBox({
    required BuildContext context,
    required String hintText,
    required String initialValue,
    required List<String> options,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          initialValue: TextEditingValue(text: initialValue),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return options;
            }
            return options.where((String option) {
              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
            });
          },
          onSelected: onSelected,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            controller.addListener(() {
              onChanged(controller.text);
            });
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: hintText,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: controller.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          controller.clear();
                          onChanged('');
                        },
                        child: const Icon(Icons.clear, size: 14),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              ),
              style: const TextStyle(fontSize: 12),
            );
          },
          optionsViewBuilder: (context, onSelectedOption, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: 180,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(option, style: const TextStyle(fontSize: 12)),
                        onTap: () => onSelectedOption(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
