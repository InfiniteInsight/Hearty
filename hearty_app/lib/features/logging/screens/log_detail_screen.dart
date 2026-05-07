import 'package:flutter/material.dart';

class LogDetailScreen extends StatelessWidget {
  final String id;

  const LogDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('/log/$id')),
    );
  }
}
