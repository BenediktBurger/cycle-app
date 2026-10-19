import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/custom_categories.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// The settings card for the user-defined diary categories: rename,
// visibility, entries and order per category, all guards (trim, caps,
// duplicates) enforced here at write time.
final class CustomCategoriesCard extends ConsumerWidget {
  const CustomCategoriesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(customDiaryCategoriesProvider);
    final notifier = ref.read(customDiaryCategoriesProvider.notifier);
    return Card(
      key: const ValueKey('customCategoriesCard'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsCustomCategoriesTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsCustomCategoriesNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (var i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _CategoryRow(
                key: ValueKey('customCategoryRow-$i-${categories[i].name}'),
                index: i,
                category: categories[i],
                categories: categories,
                onChange: notifier.set,
              ),
            ],
            const SizedBox(height: 16),
            _AddCategoryField(
              categories: categories,
              onAdded: (name) =>
                  notifier.set([...categories, CustomCategory(name: name)]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Why a category-name input is rejected. The empty case is a no-op for the
/// add flow and an error for the rename flow, so it is only surfaced where
/// the caller decides it is one.
enum _NameRejection { empty, tooLong, duplicate, categoryLimit }

/// The guard behind both category-name flows (add and rename): trims are
/// done by the caller, `original` is the renamed category's current name
/// (null for a new one) and is exempt from the duplicate check.
_NameRejection? _checkName(
  String trimmed, {
  required String? original,
  required List<CustomCategory> categories,
}) {
  if (trimmed.isEmpty) return _NameRejection.empty;
  if (trimmed.length > customLabelMaxLength) return _NameRejection.tooLong;
  if (categories.any((c) => c.name == trimmed && c.name != original)) {
    return _NameRejection.duplicate;
  }
  if (original == null && categories.length >= maxCustomCategories) {
    return _NameRejection.categoryLimit;
  }
  return null;
}

enum _EntryRejection { tooLong, duplicate, entryLimit }

_EntryRejection? _checkEntry(String trimmed, List<String> items) {
  if (trimmed.length > customLabelMaxLength) return _EntryRejection.tooLong;
  if (items.contains(trimmed)) return _EntryRejection.duplicate;
  if (items.length >= maxCustomCategoryEntries) {
    return _EntryRejection.entryLimit;
  }
  return null;
}

String _nameErrorText(_NameRejection rejection, AppLocalizations l10n) =>
    switch (rejection) {
      _NameRejection.empty => l10n.settingsCustomCategoriesErrorEmpty,
      _NameRejection.tooLong => l10n.settingsCustomCategoriesErrorTooLong(
        customLabelMaxLength,
      ),
      _NameRejection.duplicate => l10n.settingsCustomCategoriesErrorDuplicate,
      _NameRejection.categoryLimit =>
        l10n.settingsCustomCategoriesErrorCategoryLimit(maxCustomCategories),
    };

String _entryErrorText(_EntryRejection rejection, AppLocalizations l10n) =>
    switch (rejection) {
      _EntryRejection.tooLong => l10n.settingsCustomCategoriesErrorTooLong(
        customLabelMaxLength,
      ),
      _EntryRejection.duplicate =>
        l10n.settingsCustomCategoriesErrorDuplicateEntry,
      _EntryRejection.entryLimit =>
        l10n.settingsCustomCategoriesErrorEntryLimit(maxCustomCategoryEntries),
    };

extension _CategoryEdit on CustomCategory {
  CustomCategory withName(String name) =>
      CustomCategory(name: name, visible: visible, items: items);

  CustomCategory withVisible(bool visible) =>
      CustomCategory(name: name, visible: visible, items: items);

  CustomCategory withEntryAdded(String entry) =>
      CustomCategory(name: name, visible: visible, items: [...items, entry]);

  CustomCategory withEntryRemoved(int index) => CustomCategory(
    name: name,
    visible: visible,
    items: [
      for (var k = 0; k < items.length; k++)
        if (k != index) items[k],
    ],
  );
}

/// One category's management block: rename field, visibility, order,
/// delete, and its entry list with the add-entry flow.
final class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    required super.key,
    required this.index,
    required this.category,
    required this.categories,
    required this.onChange,
  });

  final int index;
  final CustomCategory category;
  final List<CustomCategory> categories;
  final ValueChanged<List<CustomCategory>> onChange;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

final class _CategoryRowState extends State<_CategoryRow> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.category.name,
  );
  final TextEditingController _entryController = TextEditingController();
  String? _nameError;
  String? _entryError;

  @override
  void dispose() {
    _nameController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _replace(CustomCategory updated) {
    widget.onChange([
      for (var i = 0; i < widget.categories.length; i++)
        if (i == widget.index) updated else widget.categories[i],
    ]);
  }

  void _remove() {
    widget.onChange([
      for (var i = 0; i < widget.categories.length; i++)
        if (i != widget.index) widget.categories[i],
    ]);
  }

  void _move(int offset) {
    final target = widget.index + offset;
    final next = List<CustomCategory>.of(widget.categories);
    next.insert(target, next.removeAt(widget.index));
    widget.onChange(next);
  }

  void _commitRename() {
    final trimmed = _nameController.text.trim();
    if (trimmed == widget.category.name) {
      setState(() => _nameError = null);
      return;
    }
    final rejection = _checkName(
      trimmed,
      original: widget.category.name,
      categories: widget.categories,
    );
    if (rejection != null) {
      setState(
        () => _nameError = _nameErrorText(
          rejection,
          AppLocalizations.of(context),
        ),
      );
      return;
    }
    _replace(widget.category.withName(trimmed));
    setState(() => _nameError = null);
  }

  void _addEntry() {
    final trimmed = _entryController.text.trim();
    if (trimmed.isEmpty) return;
    final rejection = _checkEntry(trimmed, widget.category.items);
    if (rejection != null) {
      setState(
        () => _entryError = _entryErrorText(
          rejection,
          AppLocalizations.of(context),
        ),
      );
      return;
    }
    _replace(widget.category.withEntryAdded(trimmed));
    _entryController.clear();
    setState(() => _entryError = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefix = '${widget.index}-${widget.category.name}';
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('customCategoryNameField-$prefix'),
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.settingsCustomCategoriesNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _commitRename(),
                  ),
                ),
                IconButton(
                  key: ValueKey('customCategoryMoveUp-$prefix'),
                  tooltip: l10n.settingsCustomCategoriesMoveUpTooltip,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: widget.index == 0 ? null : () => _move(-1),
                ),
                IconButton(
                  key: ValueKey('customCategoryMoveDown-$prefix'),
                  tooltip: l10n.settingsCustomCategoriesMoveDownTooltip,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: widget.index == widget.categories.length - 1
                      ? null
                      : () => _move(1),
                ),
                IconButton(
                  key: ValueKey('customCategoryDelete-$prefix'),
                  tooltip: l10n.settingsCustomCategoriesDeleteTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _remove,
                ),
              ],
            ),
            if (_nameError != null)
              Text(
                _nameError!,
                key: ValueKey('customCategoryNameError-$prefix'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            SwitchListTile(
              key: ValueKey('customCategoryVisibleSwitch-$prefix'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.settingsCustomCategoriesVisibleLabel),
              value: widget.category.visible,
              onChanged: (visible) =>
                  _replace(widget.category.withVisible(visible)),
            ),
            for (var j = 0; j < widget.category.items.length; j++)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.category.items[j],
                      key: ValueKey(
                        'customCategoryEntry-$prefix-$j-${widget.category.items[j]}',
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'customCategoryEntryRemove-$prefix-$j-${widget.category.items[j]}',
                    ),
                    tooltip: l10n.settingsCustomCategoriesRemoveEntryTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        _replace(widget.category.withEntryRemoved(j)),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('customCategoryEntryField-$prefix'),
                    controller: _entryController,
                    decoration: InputDecoration(
                      labelText: l10n.settingsCustomCategoriesEntryLabel,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addEntry(),
                  ),
                ),
                IconButton(
                  key: ValueKey('customCategoryEntryAdd-$prefix'),
                  tooltip: l10n.settingsCustomCategoriesAddEntryTooltip,
                  icon: const Icon(Icons.add),
                  onPressed: _addEntry,
                ),
              ],
            ),
            if (_entryError != null)
              Text(
                _entryError!,
                key: ValueKey('customCategoryEntryError-$prefix'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The card's "add category" flow: input field and add button, guards
/// applied on press.
final class _AddCategoryField extends StatefulWidget {
  const _AddCategoryField({required this.categories, required this.onAdded});

  final List<CustomCategory> categories;
  final ValueChanged<String> onAdded;

  @override
  State<_AddCategoryField> createState() => _AddCategoryFieldState();
}

final class _AddCategoryFieldState extends State<_AddCategoryField> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    final rejection = _checkName(
      trimmed,
      original: null,
      categories: widget.categories,
    );
    if (rejection != null) {
      setState(() => _error = _errorText(rejection));
      return;
    }
    widget.onAdded(trimmed);
    _controller.clear();
    setState(() => _error = null);
  }

  String _errorText(_NameRejection rejection) =>
      _nameErrorText(rejection, AppLocalizations.of(context));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('customCategoryAddField'),
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: l10n.settingsCustomCategoriesAddLabel,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                IconButton(
                  key: const ValueKey('customCategoryAddButton'),
                  tooltip: l10n.settingsCustomCategoriesAddTooltip,
                  icon: const Icon(Icons.add),
                  onPressed: _submit,
                ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('customCategoryAddError'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
