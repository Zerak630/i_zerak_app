import 'package:flutter/material.dart';

/// THIS CLASS DOES NOT WORK YET.
/// Please use DropdownButtonFormField instead.
///
/// See the issue related here : https://github.com/flutter/flutter/issues/141941
class DropdownMenuFormField<T> extends FormField<T> {
  DropdownMenuFormField({
    super.key,
    bool enabled = true,
    double? width,
    double? menuHeight,
    T? value,
    Icon? leadingIcon,
    Icon? trailingIcon,
    Widget? label,
    String? hintText,
    String? helperText,
    String? errorText,
    Widget? selectedTrailingIcon,
    bool enableFilter = false,
    bool enableSearch = true,
    TextStyle? textStyle,
    InputDecorationTheme? inputDecorationTheme,
    MenuStyle? menuStyle,
    this.controller,
    T? initialSelection,
    this.onSelected,
    bool? requestFocusOnTap,
    EdgeInsets? expandedInsets,
    required List<DropdownMenuEntry<T>> dropdownMenuEntries,
    AutovalidateMode? autovalidateMode = AutovalidateMode.disabled,
    super.validator,
  }) : super(
            initialValue: initialSelection,
            autovalidateMode: autovalidateMode,
            builder: (FormFieldState<T> field) {
              final _DropdownMenuFormFieldState<T> state = field as _DropdownMenuFormFieldState<T>;

              return DropdownMenu<T>(
                enabled: enabled,
                initialSelection: state.value,
                width: width,
                menuHeight: menuHeight,
                leadingIcon: leadingIcon,
                trailingIcon: trailingIcon,
                label: label,
                hintText: hintText,
                helperText: helperText,
                errorText: state.errorText,
                selectedTrailingIcon: selectedTrailingIcon,
                enableFilter: enableFilter,
                enableSearch: enableSearch,
                textStyle: textStyle,
                menuStyle: menuStyle,
                controller: controller,
                onSelected: onSelected,
                requestFocusOnTap: requestFocusOnTap,
                expandedInsets: expandedInsets,
                dropdownMenuEntries: dropdownMenuEntries,
              );
            });

  final ValueChanged<T?>? onSelected;

  final TextEditingController? controller;

  @override
  FormFieldState<T> createState() => _DropdownMenuFormFieldState<T>();
}

class _DropdownMenuFormFieldState<T> extends FormFieldState<T> {
  DropdownMenuFormField<T> get _dropdownMenuFormField => widget as DropdownMenuFormField<T>;

  @override
  void initState() {
    super.initState();
    setValue(_dropdownMenuFormField.initialValue);
  }

  @override
  void didChange(T? value) {
    super.didChange(value);
    _dropdownMenuFormField.onSelected!(value);
  }

  @override
  void didUpdateWidget(DropdownMenuFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  @override
  void reset() {
    super.reset();
    _dropdownMenuFormField.onSelected!(value);
  }
}
