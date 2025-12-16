# Contributing to GitQuick

First off, thank you for considering contributing to GitQuick! It's people like you that make GitQuick such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the issue list as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed after following the steps**
- **Explain which behavior you expected to see instead and why**
- **Include screenshots and animated GIFs if applicable**
- **Include the output of `gq config`** (redact sensitive information)
- **Include your OS version and shell type**

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Use a clear and descriptive title**
- **Provide a step-by-step description of the suggested enhancement**
- **Provide specific examples to demonstrate the steps**
- **Describe the current behavior and explain which behavior you expected to see instead**
- **Explain why this enhancement would be useful**

### Pull Requests

- Fill in the required template
- Do not include issue numbers in the PR title
- Include screenshots and animated GIFs in your pull request whenever possible
- Follow the [Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Include thoughtfully-worded, well-structured tests
- Document new code based on the [Documentation Styleguide](#documentation-styleguide)
- End all files with a newline
- Place requires in the following order:
  - Standard library
  - Third party
  - Local application/library specific
- Avoid platform-dependent code

## Development Process

1. Fork the repo and create your branch from `main`
2. Make your changes
3. Test your changes thoroughly
4. Update documentation if needed
5. Commit your changes (you can use `gq` for this!)
6. Push to your fork and submit a pull request

## Shell Script Style Guide

- Use 2 spaces for indentation
- Use `#!/usr/bin/env bash` for bash scripts
- Quote all variables: `"$variable"` instead of `$variable`
- Use `[[ ]]` instead of `[ ]` for conditionals
- Use `local` for function-scoped variables
- Add comments for complex logic
- Keep functions focused and small

## Python Style Guide

- Follow PEP 8
- Use type hints where appropriate
- Add docstrings to functions and classes
- Keep functions focused and small
- Use meaningful variable names

## Testing

Before submitting your pull request, please test:

- [ ] All existing functionality still works
- [ ] New functionality works as expected
- [ ] Error handling is appropriate
- [ ] Documentation is updated
- [ ] No sensitive data is committed

## Documentation Styleguide

- Use Markdown for all documentation
- Use code blocks with syntax highlighting
- Include examples for new features
- Update the README.md if adding new commands
- Keep documentation concise but complete

## Questions?

Feel free to open an issue for any questions you might have.
