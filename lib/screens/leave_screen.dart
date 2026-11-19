import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/action_result.dart';
import '../models/leave_type.dart';
import '../providers/leave_viewmodel.dart';
import '../providers/view_state.dart';
import '../utils/company_clock.dart';
import '../utils/date_formats.dart';
import '../widgets/leave_request_card.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();
  LeaveType _type = LeaveType.casual;
  DateTime? _start;
  DateTime? _end;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LeaveViewModel>(
      builder: (BuildContext context, LeaveViewModel vm, _) {
        if (vm.state == ViewState.initial || vm.state == ViewState.loading) {
          return const LoadingView(message: 'Loading leave information…');
        }
        if (vm.state == ViewState.error) {
          return ErrorView(
            message: vm.errorMessage ?? 'Unable to load leave information.',
            onRetry: vm.load,
          );
        }

        final balance = vm.balance;
        return RefreshIndicator(
          onRefresh: vm.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              // Leave balance, form and queue are local-first. A failed
              // background refresh must never show as a form error.
              if (vm.isRefreshing)
                const LinearProgressIndicator(minHeight: 2),
              if (vm.isRefreshing) const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _BalanceBox(
                          label: 'Casual',
                          value: balance?.casual ?? 0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BalanceBox(
                          label: 'Sick',
                          value: balance?.sick ?? 0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BalanceBox(
                          label: 'Total',
                          value: balance?.total ?? 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Apply for leave'),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        DropdownButtonFormField<LeaveType>(
                          initialValue: _type,
                          decoration: const InputDecoration(
                            labelText: 'Leave type',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items: LeaveType.values
                              .map(
                                (LeaveType type) => DropdownMenuItem<LeaveType>(
                                  value: type,
                                  child: Text(type.label),
                                ),
                              )
                              .toList(),
                          onChanged: (LeaveType? value) {
                            if (value != null) {
                              setState(() => _type = value);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        _DateField(
                          label: 'Start date',
                          date: _start,
                          clock: vm.clock,
                          onTap: () => _pickDate(context, vm, true),
                        ),
                        const SizedBox(height: 14),
                        _DateField(
                          label: 'End date',
                          date: _end,
                          clock: vm.clock,
                          onTap: () => _pickDate(context, vm, false),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _reasonController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            alignLabelWithHint: true,
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Icon(Icons.notes_outlined),
                            ),
                          ),
                          validator: (String? value) {
                            final int length = (value ?? '')
                                .replaceAll(RegExp(r'\s'), '')
                                .length;
                            if (length < 10) {
                              return 'Enter at least 10 non-whitespace characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        if (vm.isOffline)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'You are offline. Your request will be saved as '
                              'Pending Sync and submitted automatically when '
                              'the connection returns.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        if (vm.isOffline) const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: vm.isSubmitting
                              ? null
                              : () => _submit(context, vm),
                          icon: vm.isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            vm.isSubmitting ? 'Submitting…' : 'Submit request',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'My leave requests',
                action: Text(
                  vm.pendingSyncCount > 0
                      ? '${vm.requests.length} total • ${vm.pendingSyncCount} pending sync'
                      : '${vm.requests.length} total',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (vm.requests.isEmpty)
                const EmptyView(
                  message: 'No leave requests have been submitted yet.',
                  icon: Icons.event_busy_outlined,
                )
              else
                ...vm.requests.map(
                  (request) => LeaveRequestCard(request: request),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    LeaveViewModel vm,
    bool isStart,
  ) async {
    final DateTime today = _companyToday(vm.clock);
    final DateTime firstDate = isStart
        ? today
        : (_start != null && !_start!.isBefore(today) ? _start! : today);
    final DateTime selected = (isStart ? _start : _end) ?? firstDate;
    final DateTime initialDate =
        selected.isBefore(firstDate) ? firstDate : selected;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 2, 12, 31),
      helpText: isStart ? 'Select start date' : 'Select end date',
    );
    if (picked == null || !context.mounted) return;
    if (picked.isBefore(firstDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Past dates and dates before the start date are not allowed.'),
        ),
      );
      return;
    }

    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = null;
      } else {
        _end = picked;
      }
    });
  }

  DateTime _companyToday(CompanyClock clock) {
    final DateTime now = clock.companyNow;
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _submit(BuildContext context, LeaveViewModel vm) async {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both start and end dates.')),
      );
      return;
    }
    final String? dateError = vm.validateDates(
      startDate: _start!,
      endDate: _end!,
    );
    if (dateError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dateError)),
      );
      return;
    }
    final ActionResult result = await vm.submit(
      type: _type,
      startDate: _start!,
      endDate: _end!,
      reason: _reasonController.text,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
    if (result.success && mounted) {
      setState(() {
        _start = null;
        _end = null;
        _reasonController.clear();
        _formKey.currentState!.reset();
      });
    }
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final CompanyClock clock;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.date,
    required this.clock,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String text = date == null
        ? 'Not selected'
        : DateFormats.dayMonth(clock.keyFromLocalDate(date!));
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(text, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _BalanceBox extends StatelessWidget {
  final String label;
  final int value;

  const _BalanceBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Text('$value',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
