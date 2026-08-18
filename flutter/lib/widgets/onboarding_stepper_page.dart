import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter/material.dart';

import 'package:zkp_recovery_app/models/download_status.dart';
import 'package:zkp_recovery_app/services/download_service.dart';
import 'package:zkp_recovery_app/services/proof_service.dart';
import 'checklist_step_content.dart';
import 'download_step_content.dart';
import 'input_step_content.dart';
import 'output_step_content.dart';
import 'welcome_step_content.dart';

class OnboardingStepperPage extends StatefulWidget {
  const OnboardingStepperPage({super.key});

  @override
  State<OnboardingStepperPage> createState() => _OnboardingStepperPageState();
}

class _OnboardingStepperPageState extends State<OnboardingStepperPage> {
  static const int _stepWelcome = 0;
  static const int _stepChecklist = 1;
  static const int _stepDownload = 2;
  static const int _stepInput = 3;
  static const int _stepOutput = 4;

  int _currentStep = _stepWelcome;

  // --- Checklist state ---
  final List<bool> _checkedFlags = List<bool>.filled(
    prepChecklistItems.length,
    false,
  );
  bool get _allChecked => _checkedFlags.every((c) => c);

  // --- Download state ---
  final FileDownloadProgress _downloadProgress = FileDownloadProgress();
  bool get _allDownloaded =>
      _downloadProgress.state == DownloadState.downloaded;

  // --- Input state ---
  final _inputFormKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _mnemonicController = TextEditingController();
  final _evmAddressController = TextEditingController();
  final _zilAddressController = TextEditingController();
  Language _mnemonicLanguage = Language.english;
  Wallets _wallet = Wallets.ledger;
  bool _obscureMnemonic = true;
  bool _obscurePassword = true;
  bool _isComputingProof = false;
  String? _computeError;

  // --- Output state ---
  ProofResult? _proofResult;

  @override
  void initState() {
    super.initState();
    _download();
  }

  @override
  void dispose() {
    _mnemonicController.dispose();
    _evmAddressController.dispose();
    _zilAddressController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    await DownloadService.instance.checkAndDownload((progress) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.state = progress.state;
        _downloadProgress.fractionComplete = progress.fractionComplete;
        _downloadProgress.errorMessage = progress.errorMessage;
      });
    });
  }

  bool get _canContinueFromCurrentStep {
    switch (_currentStep) {
      case _stepWelcome:
        return true;
      case _stepChecklist:
        return _allChecked;
      case _stepDownload:
        return _allDownloaded;
      case _stepInput:
        return !_isComputingProof;
      case _stepOutput:
        return false; // no "continue" past the final step
      default:
        return false;
    }
  }

  Future<void> _handleContinue() async {
    switch (_currentStep) {
      case _stepWelcome:
      case _stepChecklist:
      case _stepDownload:
        if (_canContinueFromCurrentStep) {
          setState(() => _currentStep++);
        }
        break;
      case _stepInput:
        await _submitInputStep();
        break;
      default:
        break;
    }
  }

  void _handleCancel() {
    if (_currentStep > _stepWelcome) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _submitInputStep() async {
    setState(() => _computeError = null);
    if (!_inputFormKey.currentState!.validate()) return;

    setState(() => _isComputingProof = true);
    try {
      final result = await ProofService.instance.computeGroth16Proof(
        passphrase: _passwordController.text.trim(),
        mnemonic: _mnemonicController.text.trim(),
        eAddress: _evmAddressController.text.trim(),
        zAddress: _zilAddressController.text.trim(),
        language: _mnemonicLanguage,
        wallet: _wallet,
      );
      _mnemonicController.clear();
      if (!mounted) return;
      setState(() {
        _proofResult = result;
        _isComputingProof = false;
        _currentStep = _stepOutput;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _computeError = 'Failed to compute proof: $e';
        _isComputingProof = false;
      });
    }
  }

  void _restart() {
    setState(() {
      _currentStep = _stepWelcome;
      _mnemonicController.clear();
      _evmAddressController.clear();
      _zilAddressController.clear();
      _computeError = null;
      _proofResult = null;
      for (var i = 0; i < _checkedFlags.length; i++) {
        _checkedFlags[i] = false;
      }
    });
  }

  StepState _stepState(int index) {
    if (index < _currentStep) return StepState.complete;
    if (index == _currentStep) return StepState.editing;
    return StepState.indexed;
  }

  List<Step> get _steps => [
    Step(
      title: const Text('Onboarding'),
      subtitle: const Text('How this app works'),
      state: _stepState(_stepWelcome),
      isActive: _currentStep >= _stepWelcome,
      content: const Align(
        alignment: Alignment.centerLeft,
        child: WelcomeStepContent(),
      ),
    ),
    Step(
      title: const Text('Requirements'),
      subtitle: const Text('Gather the following information'),
      state: _stepState(_stepChecklist),
      isActive: _currentStep >= _stepChecklist,
      content: Align(
        alignment: Alignment.centerLeft,
        child: ChecklistStepContent(
          checkedFlags: _checkedFlags,
          onToggle: (index) {
            setState(() => _checkedFlags[index] = !_checkedFlags[index]);
          },
        ),
      ),
    ),
    Step(
      title: const Text('Downloads'),
      subtitle: const Text('Required to generate your proof'),
      state: _stepState(_stepDownload),
      isActive: _currentStep >= _stepDownload,
      content: Align(
        alignment: Alignment.centerLeft,
        child: DownloadStepContent(
          progress: _downloadProgress,
          onRetry: _download,
        ),
      ),
    ),
    Step(
      title: const Text('Account details'),
      subtitle: const Text('Seed phrase and new EVM account'),
      state: _stepState(_stepInput),
      isActive: _currentStep >= _stepInput,
      content: Align(
        alignment: Alignment.centerLeft,
        child: InputStepContent(
          formKey: _inputFormKey,
          passwordController: _passwordController,
          mnemonicController: _mnemonicController,
          evmAddressController: _evmAddressController,
          zilAddressController: _zilAddressController,
          obscureMnemonic: _obscureMnemonic,
          obscurePassword: _obscurePassword,
          isComputingProof: _isComputingProof,
          onSelectedWallet: (Wallets? wallet) => {
            setState(() => _wallet = wallet!),
          },
          onSelectedLanguage: (Language? lang) => {
            setState(() => _mnemonicLanguage = lang!),
          },
          onToggleObscure: () =>
              setState(() => _obscureMnemonic = !_obscureMnemonic),
          onTogglePassword: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          computeError: _computeError,
        ),
      ),
    ),
    Step(
      title: const Text('Proof'),
      subtitle: const Text('Submit this for verification'),
      state: _stepState(_stepOutput),
      isActive: _currentStep >= _stepOutput,
      content: Align(
        alignment: Alignment.centerLeft,
        child: OutputStepContent(result: _proofResult),
      ),
    ),
  ];

  Widget _stepIconsBuilder(int step, StepState state) {
    final theme = Theme.of(context);
    switch (state) {
      case StepState.editing:
        return Text(
          (step + 1).toString(),
          style: TextStyle(color: theme.canvasColor),
        );
      case StepState.indexed:
        return Text(
          (step + 1).toString(),
          style: TextStyle(color: theme.hintColor),
        );
      case StepState.complete:
        return Icon(Icons.check_circle, color: theme.scaffoldBackgroundColor);
      case StepState.error:
        return Icon(Icons.error_outline, color: theme.scaffoldBackgroundColor);
      case StepState.disabled:
        return Text(
          (step + 1).toString(),
          style: TextStyle(color: theme.disabledColor),
        );
    }
  }

  Widget _controlsBuilder(BuildContext context, ControlsDetails details) {
    final isLastStep = _currentStep == _stepOutput;
    final isInputStep = _currentStep == _stepInput;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (!isLastStep)
            FilledButton(
              onPressed: _canContinueFromCurrentStep
                  ? details.onStepContinue
                  : null,
              child: _isComputingProof && isInputStep
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isInputStep ? 'Compute' : 'Continue'),
            )
          else
            TextButton(onPressed: _restart, child: const Text('Start over')),
          const SizedBox(width: 12),
          if (!isLastStep && _currentStep > _stepWelcome)
            TextButton(
              onPressed: _isComputingProof ? null : details.onStepCancel,
              child: const Text('Back'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zero Knowledge Proof'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Stepper(
          type: StepperType.vertical,
          currentStep: _currentStep,
          steps: _steps,
          onStepContinue: _handleContinue,
          onStepCancel: _handleCancel,
          onStepTapped: (index) {
            // Only allow jumping back to already-completed steps; forward
            // progress must go through validation via the Continue button.
            if (index <= _currentStep) {
              setState(() => _currentStep = index);
            }
          },
          controlsBuilder: _controlsBuilder,
          stepIconBuilder: _stepIconsBuilder,
        ),
      ),
    );
  }
}
