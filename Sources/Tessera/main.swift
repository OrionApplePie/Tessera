import TesseraKit

// The whole of the executable. Everything it does lives in the library beside it,
// so that the tests can reach it as a module rather than through a hole in an
// executable target, and so that the surface this file needs — one call — is the
// only thing the library has to make public.
TesseraApp.main()
