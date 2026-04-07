import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_text_styles.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final FocusNode? focusNode;
  final FocusNode? nextFocus;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final int maxLines;
  final Widget? suffix;
  final bool monospace;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.focusNode,
    this.nextFocus,
    this.keyboardType  = TextInputType.text,
    this.formatters,
    this.capitalization= TextCapitalization.none,
    this.readOnly      = false,
    this.onTap,
    this.validator,
    this.maxLines      = 1,
    this.suffix,
    this.monospace     = false,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller:           controller,
    focusNode:            focusNode,
    readOnly:             readOnly,
    onTap:                onTap,
    keyboardType:         keyboardType,
    inputFormatters:      formatters,
    textCapitalization:   capitalization,
    maxLines:             maxLines,
    validator:            validator,
    style:                monospace ? AppTextStyles.inputMono : AppTextStyles.input,
    textInputAction:      nextFocus != null ? TextInputAction.next : TextInputAction.done,
    onFieldSubmitted:     nextFocus != null ? (_) => FocusScope.of(context).requestFocus(nextFocus) : null,
    decoration: InputDecoration(
      labelText:   label,
      hintText:    hint,
      suffixIcon:  suffix,
    ),
  );
}