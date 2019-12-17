---
title: Signing HTTP Messages
abbrev:
docname: draft-richanna-http-message-signatures-latest
category: std

ipr: trust200902
area: Applications and Real-Time
workgroup: HTTP
keyword: Internet-Draft
keyword: digital-signatures
keyword: PKI

stand_alone: yes
pi: [toc, tocindent, sortrefs, symrefs, strict, compact, comments, inline, docmapping]

author:
  - ins: A. Backman
    name: Annabelle Backman
    org: Amazon
    email: richanna@amazon.com
    uri: https://www.amazon.com/

  - ins: J. Richer
    name: Justin Richer
    org: Bespoke Engineering
    email: ietf@justin.richer.org
    uri: https://bspk.io/

  - ins: M. Sporny
    name: Manu Sporny
    org: Digital Bazaar
    email: msporny@digitalbazaar.com
    uri: https://manu.sporny.org/

normative:
    RFC2104:
    RFC7230:
    HTTP: RFC7230
    RFC7540:
    FIPS186-4:
        target: https://csrc.nist.gov/publications/detail/fips/186/4/final
        title: Digital Signature Standard (DSS)
        date: 2013
    POSIX.1:
        target: https://pubs.opengroup.org/onlinepubs/9699919799/
        title: The Open Group Base Specifications Issue 7, 2018 edition
        date: 2018

informative:
    RFC3339:
    RFC6234:
    RFC7239:
    RFC8017:
    RFC8032:
    WP-HTTP-Sig-Audit:
        target: https://web-payments.org/specs/source/http-signatures-audit/
        title: Security Considerations for HTTP Signatures
        date: 2013

--- abstract

This document describes a mechanism for creating, encoding, and verifying digital signatures
or message authentication codes over content within an HTTP message.
This mechanism supports use cases where the full HTTP message may not be known to the signer,
and where the message may be transformed (e.g., by intermediaries) before reaching the verifier.

--- note_Note_to_Readers

*RFC EDITOR: please remove this section before publication*

This draft is based on draft-cavage-http-signatures-12.
[The community](https://github.com/w3c-dvcg/http-signatures/issues?page=2&q=is%3Aissue+is%3Aopen) and the authors
have identified several issues with the current text.
Additionally, the authors have identified a number of features that are required
in order to support additional use cases.
In order to preserve continuity with the effort that has been put into draft-cavage-http-signatures-12,
this draft maintains normative compatibility with it, and thus does not address these issues or include these features,
as doing so requires making backwards-incompatible changes to normative requirements.
While such changes are inevitable, the editor recommends that they be driven by working group discussion
following adoption of the draft (see {{wg-discuss}}).
The editor requests that the working group recognize the intent of this initial draft and this recommendation
when considering adoption of this draft.


--- middle

# Introduction {#intro}

Message integrity and authenticity are important security properties that are critical to the secure operation of many [RFC7230] applications.
Application developers typically rely on the transport layer to provide these properties, by operating their application over {{?RFC8446}}.
However, TLS only guarantees these properties over a single TLS connection, and the path between client and application may be composed of
multiple independent TLS connections (for example, if the application is hosted behind a TLS-terminating gateway or if the client is behind a TLS Inspection appliance).

In such cases, TLS cannot guarantee end-to-end message integrity or authenticity between the client and application.
Additionally, some operating environments present obstacles that make it impractical to use TLS, or to use features necessary to provide message authenticity.
Furthermore, some applications require the binding of an application-level key to the HTTP message, separate from any TLS certificates in use. Consequently, while TLS can meet message integrity and authenticity needs for many HTTP-based applications, it is not a universal solution.

This document defines a mechanism for providing end-to-end integrity and authenticity for content within an HTTP message.
The mechanism allows applications to create digital signatures or message authentication codes (MACs) over only that content within the message that is meaningful and appropriate for the application.
Strict canonicalization rules ensure that the verifier can verify the signature even if the message has been transformed in any of the many ways permitted by HTTP.

The mechanism described in this document consists of three parts:

- A common nomenclature and canonicalization rule set for the different protocol elements
    and other content within HTTP messages.
- Algorithms for generating and verifying signatures over HTTP message content 
    using this nomenclature and rule set.
- A mechanism for attaching a signature and related metadata to an HTTP message.


## Requirements Discussion

HTTP permits and sometimes requires intermediaries to transform messages in a variety of ways.
This may result in a recipient receiving a message that is not bitwise equivalent to the message that was oringally sent.
In such a case, the recipient will be unable to verify a signature over the raw bytes of the sender's HTTP message, as verifying digital signatures or MACs requires both signer and verifier to have the exact same signed content.
Since the raw bytes of the message cannot be relied upon as signed content, the signer and verifier must derive the signed content from their respective versions of the message, via a mechanism that is resilient to safe changes that do not alter the meaning of the message.

For a variety of reasons, it is impractical to strictly define what constitutes a safe change versus an unsafe one.
Applications use HTTP in a wide variety of ways, and may disagree on whether a particular piece of information in a message (e.g., the body, or the Date header field) is relevant.
Thus a general purpose solution must provide signers with some degree of control over which message content is signed.

HTTP applications may be running in environments that do not provide complete access to or control over HTTP messages (such as a web browser's JavaScript environment), or may be using libraries that abstract away the details of the protocol (such as [the Java HTTPClient library](https://openjdk.java.net/groups/net/httpclient/intro.html)).
These applications need to be able to generate and verify signatures despite incomplete knowledge of the HTTP message.

## HTTP Message Transformations {#about_sigs}

As mentioned earlier, HTTP explicitly permits and in some cases requires implementations to transform messages in a variety of ways.
Implementations are required to tolerate many of these transformations.
What follows is a non-normative and non-exhaustive list of transformations
that may occur under HTTP, provided as context:

- Re-ordering of header fields with different header field names ([HTTP], Section 3.2.2).
- Combination of header fields with the same field name ([HTTP], Section 3.2.2).
- Removal of header fields listed in the Connection header field ([HTTP], Section 6.1).
- Addition of header fields that indicate control options ([HTTP], Section 6.1).
- Addition or removal of a transfer coding ([HTTP], Section 5.7.2).
- Addition of header fields such as Via ([HTTP], Section 5.7.1) and Forwarded ([RFC7239], Section 4).

## Safe Transformations

Based on the definition of HTTP and the requirements described above, we can identify certain types of transformations that should not prevent signature verification, even when performed on content covered by the signature.
The following list describes those transformations:

Additionally, all changes to content not covered by the signature are considered safe.

- Combination of header fields with the same field name.
- Reordering of header fields with different names.
- Conversion between HTTP/1.x and HTTP/2, or vice-versa.
- Changes in casing (e.g., "Origin" to "origin") of any case-insensitive content such as
  header field names, request URI scheme, or host.
- Addition or removal of leading or trailing whitespace to a header field value.
- Addition or removal of obs-folds.
- Changes to the request-target and Host header field that when applied together do not result
  in a change to the message's effective request URI, as defined in Section 5.5 of [HTTP].


## Conventions and Terminology {#definitions}

{::boilerplate bcp14}

The terms "HTTP message", "HTTP method", "HTTP request", "HTTP response",
`absolute-form`, `absolute-path`, "effective request URI", "gateway", "header field",
"intermediary", `request-target`, "sender", and "recipient" are used as defined in [RFC7230].

For brevity, the term "signature" on its own is used in this document to refer to both
digital signatures and keyed MACs. 
Similarly, the verb "sign" refers to the generation of either
a digital signature or keyed MAC over a given input string.
The qualified term "digital signature" refers specifically to the output of
an asymmetric cryptographic signing operation.

In addition to those listed above, this document uses the following terms:

Decimal String:
: An Integer String optionally concatenated with a period "." followed by a second Integer String,
 representing a positive real number expressed in base 10. 
 The first Integer String represents the integral portion of the number, 
 while the optional second Integer String represents the fractional portion of the number. 
 [[ Editor's note: There's got to be a definition for this that we can reference. ]]

Integer String:
: A US-ASCII string of one or more digits "0-9", representing a positive integer in base 10. 
  [[ Editor's note: There's got to be a definition for this that we can reference. ]]

Signer:
: The entity that is generating or has generated an HTTP Message Signature.

Verifier:
: An entity that is verifying or has verified an HTTP Message Signature against an HTTP Message.
  Note that an HTTP Message Signature may be verified multiple times, potentially by different entities.

This document contains non-normative examples of partial and complete HTTP messages.
To improve readability, header fields may be split into multiple lines, using the `obs-fold` syntax.
This syntax is deprecated in [RFC7230], and senders MUST NOT generate messages that include it.

# Identifying and Canonicalizing Content {#content-identifiers}

In order to allow signers and verifiers to establish which content is covered by a signature, this document defines content identifiers for signature metadata and discrete pieces of message content that may be covered by an HTTP Message Signature.

Some content within HTTP messages may undergo transformations that change the bitwise value without altering meaning of the content (for example, the merging together of header fields with the same name).
Message content must therefore be canonicalized before it is signed, to ensure that a signature can be verified despite such innocuous transformations.
This document defines rules for each content identifier that transform the identifier's associated content into such a canonical form.

The following sections define content identifiers, their associated content, and their canonicalization rules.

## HTTP Header Fields

An HTTP header field value is identified by its header field name.
While HTTP header field names are case-insensitive, implementations SHOULD use lowercased field names (e.g., `content-type`, `date`, `etag`) when using them as content identifiers.

An HTTP header field value is canonicalized as follows:

1. Create an ordered list of the field values of each instance of the header field in the message, in the order that they occur (or will occur) in the message.
2. Strip leading and trailing whitespace from each item in the list.
3. Concatenate the list items together, with a comma "," and space " " between each item. The resulting string is the canonicalized value.



### Canonicalization Examples

This section contains non-normative examples of canonicalized values for header fields, given the following example HTTP message:


~~~
HTTP/1.1 200 OK
Server: www.example.com
Date: Tue, 07 Jun 2014 20:51:35 GMT
X-OWS-Header:   Leading and trailing whitespace.   
X-Obs-Fold-Header: Obsolete  
    line folding.
X-Empty-Header: 
Cache-Control: max-age=60
Cache-Control:    must-revalidate
~~~

The following table shows example canonicalized values for header fields, given that message:


|Header Field|Canonicalized Value|
|--- |--- |
|(cache-control)|max-age=60, must-revalidate|
|(date)|Tue, 07 Jun 2014 20:51:35 GMT|
|(server)|www.example.com|
|(x-empty-header)||
|(x-obs-fold-header)|Obsolete line folding.|
|(x-ows-header)|Leading and trailing whitespace.|
{: title="Non-normative examples of header field canonicalization."}


## Signature Creation Time

The signature's Creation Time ({{signature-metadata}}) is identified by the `(created)` identifier.

Its canonicalized value is an Integer String containing the signature's 
Creation Time expressed as the number of seconds since the Epoch, 
as defined in [Section 4.16](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_16) of {{POSIX.1}}.

> The use of seconds since the Epoch to canonicalize a timestamp 
> simplifies processing and avoids timezone management
> required by specifications such as [RFC3339].

## Signature Expiration Time

The signature's Expiration Time ({{signature-metadata}}) is identified by the `(expired)` identifier.

Its canonicalized value is a Decimal String containing the signature's Expiration Time expressed as the number of seconds since the Epoch, as defined in [Section 4.16](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_16) of {{POSIX.1}}.

## Target Endpoint

The request target endpoint, consisting of the request method and the path and query of the effective request URI, is identified by the `(request-target)` identifier.

Its value is canonicalized as follows:

1. Take the lowercased HTTP method of the message.
2. Append a space " ".
3. Append the path and query of the request target of the message,
   formatted according to the rules defined for the :path pseudo-header
   in [HTTP2], Section 8.1.2.3.
   The resulting string is the canonicalized value.

### Canonicalization Examples

The following table contains non-normative example HTTP messages and their
canonicalized `(request-target)` values.



# HTTP Message Signatures {#message-signatures}

An HTTP Message Signature is a signature over a string generated from a subset of the content in an HTTP message and metadata about the signature itself.
When successfully verified against an HTTP message, it provides cryptographic proof that with respect to the subset of content that was signed, the message is semantically equivalent to the message for which the signature was generated.

## Signature Metadata {#signature-metadata}

HTTP Message Signatures have metadata properties that provide information regarding the signature's generation and/or verification.
The following metadata properties are defined:

## Creating a Signature {#create}

In order to create a signature, a signer completes the following process:

The following sections describe each of these steps in detail.

### Choose and Set Signature Metadata Properties {#choose-metadata}

For example, given the following HTTP message:

~~~
GET /foo HTTP/1.1
Host: example.org
Date: Tue, 07 Jun 2014 20:51:35 GMT
X-Example: Example header
        with some whitespace.
X-EmptyHeader:
Cache-Control: max-age=60
Cache-Control: must-revalidate
~~~

The following table presents a non-normative example of metadata values that a signer may choose:

|Property|Value|
|--- |--- |
|Algorithm|rsa-256|
|Covered Content|(request-target), (created), host, date, cache-contol, x-emptyheader, x-example|
|Creation Time|Equal to the value specified in the Date header field.|
|Expiration Time|Equal to the Creation Time plus five minutes.|
|Verification Key Material|The public key provided in  and identified by the keyId value "test-key-b".|
{: #example-metadata}


### Create the Signature Input {#canonicalization}

The Signature Input is a US-ASCII string containing the content that will be signed.
To create it, the signer concatenates together entries for each identifier in the signature's Covered Content in the order it occurs in the list, with each entry separated by a newline `"\n"`.
An identifier's entry is a US-ASCII string consisting of the lowercased identifier followed with a colon `":"`, a space `" "`, and the identifier's canonicalized value (described below).

If Covered Content contains `(created)` and the signature's Creation Time is undefined or the signature's Algorithm name starts with `rsa`, `hmac`, or `ecdsa` an implementation MUST produce an error.

If Covered Content contains `(expires)` and the signature does not have an Expiration Time or the signature's Algorithm name starts with `rsa`, `hmac`, or `ecdsa` an implementation MUST produce an error.

If Covered Content contains an identifier for a header field that is not present or malformed in the message, the implementation MUST produce an error.

For the non-normative example Signature metadata in {{example-metadata}},  the corresponding Signature Input is:

~~~
(request-target): get /foo
(created): 1402170695
host: example.org
date: Tue, 07 Jun 2014 20:51:35 GMT
cache-control: max-age=60, must-revalidate
x-emptyheader:
x-example: Example header with some whitespace.
~~~
{: artwork-name="example-sig-input" #example-sig-input}

### Sign the Signature Input {#sign-sig-input}

The signer signs the Signature Input using the signing algorithm described by the signature's Algorithm property, and the key material chosen by the signer.
The signer then encodes the result of that operation as a base 64-encoded string {{?RFC4648}}.
This string is the signature value.

For the non-normative example Signature metadata in {{choose-metadata}} and Signature Input in {{example-sig-input}}, the corresponding signature value is:

~~~
T1l3tWH2cSP31nfuvc3nVaHQ6IAu9YLEXg2pCeEOJETXnlWbgKtBTaXV6LNQWtf4O42V2
DZwDZbmVZ8xW3TFW80RrfrY0+fyjD4OLN7/zV6L6d2v7uBpuWZ8QzKuHYFaRNVXgFBXN3
VJnsIOUjv20pqZMKO3phLCKX2/zQzJLCBQvF/5UKtnJiMp1ACNhG8LF0Q0FPWfe86YZBB
xqrQr5WfjMu0LOO52ZAxi9KTWSlceJ2U361gDb7S5Deub8MaDrjUEpluphQeo8xyvHBoN
Xsqeax/WaHyRYOgaW6krxEGVaBQAfA2czYZhEA05Tb38ahq/gwDQ1bagd9rGnCHtAg==
~~~
{: artwork-name="example-sig-input" #example-sig-value}

## Verifying a Signature {#verify}

In order to verify a signature, a verifier MUST:

A signature with a Creation Time that is in the future or an Expiration Time that is in the past MUST NOT be processed.

The verifier MUST ensure that a signature's Algorithm is appropriate for the key material the verifier will use to verify the signature.
If the Algorithm is not appropriate for the key material (for example, if it is the wrong size, or in the wrong format), the signature MUST NOT be processed.

### Enforcing Application Requirements

The verification requirements specified in this document are intended as a baseline set of restrictions that are generally applicable to all use cases.
Applications using HTTP Message Signatures MAY impose requirements above and beyond those specified by this document, as appropriate for their use case.

Some non-normative examples of additional requirements an application might define are:

Application-specific requirements are expected and encouraged.
When an application defines additional requirements, it MUST enforce them during the signature verification process, and signature verification MUST fail if the signature does not conform to the application's requirements.

Applications MUST enforce the requirements defined in this document.
Regardless of use case, applications MUST NOT accept signatures that do not conform to these requirements.

# The 'Signature' HTTP Header {#sig}

The "Signature" HTTP header provides a mechanism to attach a signature to the HTTP message from which it was generated.
The header field name is "Signature" and its value is a list of parameters and values, formatted according to the `signature` syntax defined below, using the extended Augmented Backus-Naur Form (ABNF) notation used in [RFC7230].

Each `sig-param` is the name of a parameter defined in the {{param-registry}} defined in this document.
The initial contents of this registry are described in {{params}}.

## Signature Header Parameters {#params}

The Signature header's parameters contain the signature value itself and the signature metadata properties required to verify the signature.
Unless otherwise specified, parameters MUST NOT occur multiple times in one header, whether with the same or different values.
The following parameters are defined:

## Example

The following is a non-normative example Signature header field representing the signature in {{example-sig-value}}:

# IANA Considerations {#iana}

## HTTP Signature Algorithms Registry {#hsa-registry}

This document defines HTTP Signature Algorithms, for which IANA is asked to create and maintain a new registry titled "HTTP Signature Algorithms".
Initial values for this registry are given in {{iana-hsa-contents}}.
Future assignments and modifications to existing assignment are to be made through the Expert Review registration policy {{?RFC8126}} and shall follow the template presented in {{iana-hsa-template}}.

### Registration Template {#iana-hsa-template}

### Initial Contents {#iana-hsa-contents}

[[ MS: The references in this section are problematic as many of the specifications that they refer to are too implementation specific, rather than just pointing to the proper signature and hashing specifications.
A better approach might be just specifying the signature and hashing function specifications, leaving implementers to connect the dots (which are not that hard to connect). ]]


## HTTP Signature Parameters Registry {#param-registry}

This document defines the Signature header field, whose value contains a list of named parameters.
IANA is asked to create and maintain a new registry titled "HTTP Signature Parameters" to record and maintain the set of named parameters defined for use within the Signature header field.
Initial values for this registry are given in {{iana-param-contents}}.
Future assignments and modifications to existing assignment are to be made through the Expert Review registration policy {{?RFC8126}} and shall follow the template presented in {{iana-param-template}}.

### Registration Template {#iana-param-template}

### Initial Contents {#iana-param-contents}

The table below contains the initial contents of the HTTP Signature Parameters Registry.
Each row in the table represents a distinct entry in the registry.

# Security Considerations {#security}

[[ TODO: need to dive deeper on this section; not sure how much of what's referenced below is actually applicable, or if it covers everything we need to worry about. ]]

[[ TODO: Should provide some recommendations on how to determine what content needs to be signed for a given use case. ]]

There are a number of security considerations to take into account when implementing or utilizing this specification.
A thorough security analysis of this protocol, including its strengths and weaknesses, can be found in {{WP-HTTP-Sig-Audit}}.

--- back
# Examples

## Example Keys {#example-keys}

This section provides cryptographic keys that are referenced in example signatures throughout this document.
These keys MUST NOT be used for any purpose other than testing.

### Example Key RSA test {#example-key-rsa-test}

The following key is a 2048-bit RSA public and private key pair:

## Example 

The table below maps example `keyId` values to associated algorithms and/or keys.
These are example mappings that are valid only within the context of examples in examples within this and future documents that reference this section.
Unless otherwise specified, within the context of examples it should be assumed that the signer and verifier understand these `keyId` mappings.
These `keyId` values are not reserved, and deployments are free to use them, with these associations or others.

## Test Cases

This section provides non-normative examples that may be used as test cases to validate implementation correctness.
These examples are based on the following HTTP message:

### Signature Generation

#### hs2019 signature over minimal recommended content

This presents metadata for a Signature using `hs2019`, over minimum recommended data to sign:

The Signature Input is:

The signature value is:

A possible Signature header for this signature is:

#### "hs2019" signature covering all header fields

This presents metadata for a Signature using `hs2019` that covers all header fields in the request:

The Signature Input is:

The signature value is:

A possible Signature header for this signature is:

### Signature Verification

#### Minimal Required Signature Header

This presents a Signature header containing only the minimal required parameters:

The corresponding signature metadata derived from this header field is:

The corresponding Signature Input is:

#### Minimal Recommended Signature Header

This presents a Signature header containing only the minimal required and recommended parameters:

The corresponding signature metadata derived from this header field is:

The corresponding Signature Input is:

#### Minimal Signature Header using 

This presents a minimal Signature header for a signature using the `rsa-256` algorithm:

The corresponding signature metadata derived from this header field is:

The corresponding Signature Input is:

# Topics for Working Group Discussion {#wg-discuss}

The goal of this draft document is to provide a starting point at feature parity and compatible with the cavage-12 draft. The draft has known issues that will need to be addressed during development, and in the spirit of keeping compatibility, these issues have been enumerated but not addressed in this version. The editor recommends the working group discuss the issues and features described in this section after adoption of the document by the working group.
Topics are not listed in any particular order.

## Issues

### Confusing guidance on algorithm and key identification {#issue-alg-keyid}

The current draft encourages determining the Algorithm metadata property from the `keyId` field, both in the guidance for the use of `algorithm` and `keyId`, and the definition for the `hs2019` algorithm and deprecation of the other algorithms in the registry.
The current state arose from concern that a malicious party could change the value of the `algorithm` parameter, potentially tricking the verifier into accepting a signature that would not have been verified under the actual parameter.

Punting algorithm identification into `keyId` hurts interoperability, since we aren't defining the syntax or semantics of `keyId`.
It actually goes against that claim, as we are dictating that the signing algorithm must be specified by `keyId` or derivable from it.
It also renders the algorithm registry essentially useless.
Instead of this approach, we can protect against manipulation of the Signature header field by adding support for (and possibly mandating) including Signature metadata within the Signature Input.

### Lack of definition of 

The current text leaves the format and semantics of `keyId` completely up to the implementation.
This is primarily due to the fact that most implementers of Cavage have extensive investment in key distribution and management, and just need to plug an identifier into the header.
We should support those cases, but we also need to provide guidance for the developer that doesn't have that and just wants to know how to identify a key.
It may be enough to punt this to profiling specs, but this needs to be explored more.

### Algorithm Registry duplicates work of JWA

{{?RFC7518}} already defines an IANA registry for cryptographic algorithms.
This wasn't used by Cavage out of concerns about complexity of JOSE, and issues with JWE and JWS being too flexible, leading to insecure combinations of options.
Using JWA's definitions does not need to mean we're using JOSE, however.
We should look at if/how we can leverage JWA's work without introducing too many sharp edges for implementers.

In any use of JWS algorithms, this spec would define a way to create the JWS Signing Input string to be applied to the algorithm. It should be noted that this is incompatible with JWS itself, which requires the inclusion of a structured header in the signature input.

A possible approach is to incorporate all elements of the JWA signature algorithm registry into this spec using a prefix or other marker, such as `jws-RS256` for the RSA 256 JSON Web Signature algorithm.

### Algorithm Registry should not be initialized with deprecated entries

The initial entries in this document reflect those in Cavage.
The ones that are marked deprecated were done so because of the issue explained in {{issue-alg-keyid}}, with the possible exception of `rsa-sha1`.
We should probably just remove that one.

### No percent-encoding normalization of path/query

See: [issue #26](https://github.com/w3c-dvcg/http-signatures/issues/26)

The canonicalization rules for `(request-target)` do not perform handle minor, semantically meaningless differences in percent-encoding, such that verification could fail if an intermediary normalizes the effective request URI prior to forwarding the message.

At a minimum, they should be case and percent-encoding normalized as described in sections [6.2.2.1](RFC3986) and [6.2.2.2](RFC3986) of {{?RFC3986}}.

### Misleading name for 

The Covered Content list contains identifiers for more than just headers, so the `header` parameter name is no longer appropriate.
Some alternatives: "content", "signed-content", "covered-content".

### Changes to whitespace in header field values break verification

Some header field values contain RWS, OWS, and/or BWS.
Since the header field value canonicalization rules do not address whitespace, changes to it (e.g., removing OWS or BWS or replacing strings of RWS with a single space) can cause verification to fail.

### Multiple Set-Cookie headers are not well supported

The Set-Cookie header can occur multiple times but does not adhere to the list syntax, and thus is not well supported by the header field value concatenation rules.

### Covered Content list is not signed

The Covered Content list should be part of the Signature Input, to protect against malicious changes.

### Algorithm is not signed

The Algorithm should be part of the Signature Input, to protect against malicious changes.

### Verification key identifier is not signed

The Verification key identifier (e.g., the value used for the `keyId` parameter) should be part of the Signature Input, to protect against malicious changes.

### Max values, precision for Integer String and Decimal String not defined

The definitions for Integer String and Decimal String do not specify a maximum value.
The definition for Decimal String (used to provide sub-second precision for Expiration Time) does not define minimum or maximum precision requirements.
It should set a sane requirement here (e.g., MUST support up to 3 decimal places and no more).

### UNNAMED-1

The `keyId` parameter value needs to be constrained so as to not break list syntax (e.g., by containing a comma).

### Creation Time and Expiration Time do not allow for clock skew

The processing instructions for Creation Time and Expiration Time imply that verifiers are not permitted to account for clock skew during signature verification.

### Should require lowercased header field names as identifiers

The current text allows mixed-case header field names when they are being used as content identifiers.
This is unnecessary, as header field names are case-insensitive, and creates opportunity for incompatibility.
Instead, content identifiers should always be lowercase.

### Reconcile Date header and Creation Time

The draft is missing guidance on if/how the Date header relates to signature Creation Time.
There are cases where they may be different, such as if a signature was pre-created.
Should Creation Time default to the value in the Date header if the `created` parameter is not specified?

### Remove algorithm-specific rules for content identifiers

The rules that restrict when the signer can or must include certain identifiers appear to be related to the pseudo-revving of the Cavage draft that happened when the `hs2019` algorithm was introduced.
We should drop these rules, as it can be expected that anyone implementing this draft will support all content identifiers.

### Add guidance for signing compressed headers

The draft should provide guidance on how to sign headers when {{?RFC7541}} is used.
This guidance might be as simple as "sign the uncompressed header field value."

### Transformations to Via header field value break verification

Intermediaries are permitted to strip comments from the Via header field value, and consolidate related sequences of entries.
The canonicalization rules do not account for these changes, and thus they cause signature verification to fail if the Via header is signed. At the very least, guidance on signing or not signing Via headers needs to be included.

### Case changes to case-insensitive header field values break verification

Some header field values are case-insensitive, in whole or in part. The canonicalization rules do not account for this, thus a case change to a covered header field value causes verification to fail.

### Need more examples for Signature header

Add more examples showing different cases e.g, where `created` or `expires` are not present.

### Expiration not needed

In many cases, putting the expiration of the signature into the hands of the signer opens up more options for failures than necessary. Instead of the `expires`, any verifier can use the `created` field and an internal lifetime or offset to calculate expiration. We should consider dropping the `expires` field.

## Features

### Define more content identifiers

It should be possible to independently include the following content and metadata properties in Covered Content:

### Multiple signature support

[[ Editor's note: I believe this use case is theoretical.
Please let me know if this is a use case you have. ]]

There may be scenarios where attaching multiple signatures to a single message is useful:

This could be addressed by changing the Signature header syntax to accept a list of parameter sets for a single signature, e.g., by separating parameters with `";"` instead of `","`.
It may also be necessary to include a signature identifier parameter.

### Support for incremental signing of header field value list items

[[ Editor's note: I believe this use case is theoretical.
Please let me know if this is a use case you have. ]]

Currently, signing a header field value is all-or-nothing: either the entire value is signed, or none of it is.
For header fields that use list syntax, it would be useful to be able to specify which items in the list are signed.

A simple approach that allowed the signer to indicate the list size at signing time would allow a signer to sign header fields that are may be appended to by intermediaries as the message makes its way to the recipient.
Specifying list size in terms of number of items could introduce risks of list syntax is not strictly adhered to (e.g., a malicious party crafts a value that gets parsed by the application as 5 items, but by the verifier as 4).
Specifying list size in number of octets might address this, but more exploration is required.

### Support expected authority changes

In some cases, the authority of the effective request URI may be expected to change, for example from "public-service-name.example.com" to "service-host-1.public-service-name.example.com".
This is commonly the case for services that are hosted behind a load-balancing gateway, where the client sends requests to a publicly known domain name for the service, and these requests are transformed by the gateway into requests to specific hosts in the service fleet.

One possible way to handle this would be to special-case the Host header field to allow verifier to substitute a known expected value, or a value provided in another header field (e.g., Via) when generating the Signature Input, provided that the verifier also recognizes the real value in the Host header.
Alternatively, this logic could apply to an `(audience)` content identifier.

### Support for signing specific cookies

A signer may only wish to sign one or a few cookies, for example if the website requires its authentication state cookie to be signed, but also sets other cookies (e.g., for analytics, ad tracking, etc.)

# Acknowledgements {#acknowledgements}
{:numbered="false"}

This specification is based on the draft-cavage-http-signatures draft.
The editor would like to thank the authors of that draft, Mark Cavage and Manu Sporny, for their work on that draft and their continuing contributions.

The editor would also like to thank the following individuals for feedback on and implementations of the draft-cavage-http-signatures draft (in alphabetical order):
Mark Adamcin,
Mark Allen,
Paul Annesley,
Karl Böhlmark,
Stéphane Bortzmeyer,
Sarven Capadisli,
Liam Dennehy,
ductm54,
Stephen Farrell,
Phillip Hallam-Baker,
Eric Holmes,
Andrey Kislyuk,
Adam Knight,
Dave Lehn,
Dave Longley,
James H. Manger,
Ilari Liusvaara,
Mark Nottingham,
Yoav Nir,
Adrian Palmer,
Lucas Pardue,
Roberto Polli,
Julian Reschke,
Michael Richardson,
Wojciech Rygielski,
Adam Scarr,
Cory J. Slep,
Dirk Stein,
Henry Story,
Lukasz Szewc,
Chris Webber, and
Jeffrey Yasskin

# Document History
{:numbered="false"}

